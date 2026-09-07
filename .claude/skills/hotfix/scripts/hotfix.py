#!/usr/bin/env python
"""Ship a narrow Lua hotfix to clients already in the field, without a release.

WHAT A HOTFIX IS. Every codex file has a cloud history of revisions, each tagged
with the engine version it requires (/CodeMod/{modid}/files[i].history[]). A
client walks that history backwards and runs the newest revision whose
engineVersion is at or below its own build (CodeModFile.currentMd5 in
CodeModManager.cs). So a revision inserted at an OLD engine version reaches
clients on that old build the next time they load a game, while clients on newer
builds keep the revision tagged for them. This script builds such a revision.

It never reads the working tree. The fix is one or more commits on the codex
repo's main branch; the base is the exact text retail clients are running
(fetched by md5 from the cloud); the two are combined with a three-way merge
(git merge-file), syntax-checked with luac, uploaded to /Code/{md5} and the GCS
code bucket, and inserted into the file history at the right position with a
changelist that names the commit. An audit record goes to
/CodeModHotfix/{modid}/{changelistGuid}. `revert` undoes one.

Subcommands
  versions                  which app versions loaded a game recently (analytics)
  status  <Mod/File.lua>    a file's history tail and what each live version runs
  plan    <commit...>       compute the hotfix, show diff + reach; no writes
  apply   <commit...>       the same, then write it
  revert  <changelistGuid>  pull a hotfix back out of the history

Run `python hotfix.py <subcommand> --help` for flags.

CREDENTIAL. Needs the MCDM Firebase service-account key (mcdm-key.json). It is
NOT in the repo. Resolution order: $DMHUB_FIREBASE_KEY (a file),
$DMHUB_ADMIN_DIR/mcdm-key.json, ~/.dmhub/mcdm-key.json, then the known admin
tooling directories. The script explains itself when none is found.
"""

import argparse
import base64
import collections
import datetime
import difflib
import gzip
import hashlib
import json
import os
import subprocess
import sys
import tempfile
import urllib.parse
import uuid

SCRIPT_DIR = os.path.dirname(os.path.abspath(__file__))

DATABASE_URL = "https://mcdm-385cf-default-rtdb.firebaseio.com/"
# The retail (MCDM white-label) core mods. Every codex mod is reachable from
# these two through `dependencies` (CodeMod.BaseMod / CodeMod.OfficialMod).
CORE_MOD_ROOTS = (
    "fddd9c1c-cd4a-4091-bed2-c69bb7f81eb4",  # BaseMod
    "b4a3262f-b6ef-4427-9a94-9cc7fbfc8a33",  # OfficialMod ("Draw Steel")
)
# Where clients fetch code blobs first (ImageManager.ImageIdToCloudUrl) and the
# uploader that fills that bucket (ImageManager._imageUpload). The uploader
# validates MD5(payload) == key, so it accepts nothing but a correct blob.
GCS_DOWNLOAD = "https://storage.googleapis.com/dmhub_images/"
GCS_UPLOAD = "http://34.96.69.185:8080"

KEY_BASENAME = "mcdm-key.json"
KEY_DIR_FALLBACKS = (
    os.path.join(os.path.expanduser("~"), ".dmhub"),
    os.path.join("D:", os.sep, "dev", "dmhub-admin"),
    os.path.join("C:", os.sep, "dev", "dmhub-admin"),
    os.path.join(os.path.expanduser("~"), "dev", "dmhub-admin"),
)

NL = chr(10)


def die(msg, code=2):
    sys.stderr.write("ERROR: %s%s" % (msg, NL))
    sys.exit(code)


def note(msg=""):
    sys.stdout.write(msg + NL)
    sys.stdout.flush()


# --------------------------------------------------------------- engine versions
# Exact port of StringUtils.EngineVersionGreaterOrEqual. A missing engineVersion
# (old "Added file" entries) is null in C#, which compares below everything.

def _parse_token(s):
    dot = s.find(".")
    if dot != -1:
        remainder = s[dot + 1:]
        s = s[:dot]
    else:
        remainder = None
    suffix = ""
    while s and not s[-1].isdigit():
        suffix = s[-1] + suffix
        s = s[:-1]
    num = int(s) if s.isdigit() else 0
    return num, suffix, remainder


def version_ge(a, b):
    while a is not None and b is not None:
        na, sa, a = _parse_token(a)
        nb, sb, b = _parse_token(b)
        if na > nb:
            return True
        if na < nb:
            return False
        if sa > sb:
            return True
        if sa < sb:
            return False
    if a is None and b is None:
        return True
    return a is not None and b is None


def version_gt(a, b):
    return version_ge(a, b) and not version_ge(b, a)


def entry_version(entry):
    return entry.get("engineVersion") or None


def resolve_index(history, client_version):
    """Index of the history entry a client on `client_version` runs (currentMd5)."""
    i = len(history) - 1
    while i >= 0 and version_gt(entry_version(history[i]), client_version):
        i -= 1
    return i


def insert_index(history, hotfix_version):
    """Where CommitChanges would insert an entry tagged `hotfix_version`."""
    i = len(history)
    while i > 0 and version_gt(entry_version(history[i - 1]), hotfix_version):
        i -= 1
    return i


# ----------------------------------------------------------------------- code
def code_md5(text):
    return hashlib.md5(text.encode("utf-8")).hexdigest().upper()


def to_unix(text):
    return text.replace("\r\n", "\n").replace("\r", "\n")


def compress_code(text):
    return base64.b64encode(gzip.compress(text.encode("utf-8"))).decode("ascii")


def decompress_code(b64):
    return gzip.decompress(base64.b64decode(b64)).decode("utf-8")


def gcs_key(md5hex):
    """Md5HexToGCSKey + UrlifyBase64: the object name in the code bucket."""
    b64 = base64.b64encode(bytes.fromhex(md5hex)).decode("ascii")
    return b64.replace("/", "-").replace("+", "_").replace("=", "~")


def gcs_url(md5hex):
    return GCS_DOWNLOAD + urllib.parse.quote(gcs_key(md5hex))


# ------------------------------------------------------------------- firebase
_db = None


def key_candidates():
    env_file = os.environ.get("DMHUB_FIREBASE_KEY")
    if env_file:
        yield env_file
    env_dir = os.environ.get("DMHUB_ADMIN_DIR")
    if env_dir:
        yield os.path.join(env_dir, KEY_BASENAME)
    for d in KEY_DIR_FALLBACKS:
        yield os.path.join(d, KEY_BASENAME)


def find_key():
    for p in key_candidates():
        if p and os.path.isfile(p):
            return p
    return None


def missing_key_message():
    lines = [
        "No Firebase service-account key found. The hotfix script writes to the",
        "MCDM Realtime Database directly, so it needs %s." % KEY_BASENAME,
        "",
        "Looked in (first match wins):",
    ]
    for p in key_candidates():
        lines.append("  - %s" % p)
    lines += [
        "",
        "Put the key at one of those paths, or point at it with $DMHUB_FIREBASE_KEY.",
        "Never copy it into a repository directory.",
    ]
    return NL.join(lines)


def db():
    global _db
    if _db is not None:
        return _db
    key = find_key()
    if key is None:
        die(missing_key_message())
    try:
        import firebase_admin
        from firebase_admin import credentials
        from firebase_admin import db as fdb
    except ImportError:
        die("firebase_admin is not installed: pip install -r %s" % os.path.join(SCRIPT_DIR, "requirements.txt"))
    firebase_admin.initialize_app(credentials.Certificate(key), {"databaseURL": DATABASE_URL})
    _db = fdb
    return _db


def ref(path):
    return db().reference(path)


# -------------------------------------------------------------------- mods
_mod_names = None


def core_mod_index():
    """{name: guid} for every mod reachable from the retail core roots.

    Mod directory names in the codex repo ARE mod names (GitModManager.PathToName),
    which is how a commit path maps to a cloud record. Fetches only name +
    dependencies per mod, not the bodies."""
    global _mod_names
    if _mod_names is not None:
        return _mod_names
    names = {}
    seen = set()
    stack = list(CORE_MOD_ROOTS)
    while stack:
        guid = stack.pop()
        if guid in seen:
            continue
        seen.add(guid)
        name = ref("/CodeMod/%s/name" % guid).get()
        deps = ref("/CodeMod/%s/dependencies" % guid).get() or []
        if name is None:
            continue
        if name in names and names[name] != guid:
            die("Two core mods are both named %r (%s, %s); cannot map paths by name." % (name, names[name], guid))
        names[name] = guid
        stack.extend(d for d in deps if d)
    _mod_names = names
    return names


def fetch_mod(guid, with_etag=False):
    r = ref("/CodeMod/%s" % guid)
    if with_etag:
        value, etag = r.get(etag=True)
        return value, etag
    return r.get()


def find_file(mod, fname):
    for i, f in enumerate(mod.get("files") or []):
        if f and f.get("name") == fname:
            return i, f
    return -1, None


def split_repo_path(path):
    """'Draw Steel Core Rules/MCDMCreature.lua' -> ('Draw Steel Core Rules', 'MCDMCreature')."""
    path = path.replace("\\", "/")
    parts = path.split("/")
    if len(parts) != 2 or not parts[1].lower().endswith(".lua"):
        return None
    return parts[0], parts[1][:-4]


# ------------------------------------------------------------------- code io
def fetch_code(md5hex):
    """The exact text behind a history md5: GCS bucket first, then RTDB."""
    try:
        import requests
        r = requests.get(gcs_url(md5hex), timeout=60)
        if r.status_code == 200:
            text = r.content.decode("utf-8")
            if code_md5(text) == md5hex:
                return text, "gcs"
    except Exception:
        pass
    b64 = ref("/Code/%s" % md5hex).get()
    if not isinstance(b64, str):
        die("No code found in the cloud for md5 %s" % md5hex)
    text = decompress_code(b64)
    if code_md5(text) != md5hex:
        die("Cloud code for %s does not hash to its own key; refusing to build on it." % md5hex)
    return text, "rtdb"


def upload_code(md5hex, text):
    """Mirror of CodeModManager.UploadCode: RTDB entry (skip if present) + GCS blob."""
    existing = ref("/Code/%s" % md5hex).get()
    if isinstance(existing, str):
        if decompress_code(existing) != text:
            die("/Code/%s already exists with DIFFERENT content. Aborting." % md5hex)
        note("  /Code/%s already present" % md5hex)
    else:
        ref("/Code/%s" % md5hex).set(compress_code(text))
        note("  wrote /Code/%s" % md5hex)
    import requests
    try:
        r = requests.get(gcs_url(md5hex), timeout=30)
        if r.status_code == 200 and r.content == text.encode("utf-8"):
            note("  GCS blob already present")
            return
    except Exception:
        pass
    try:
        r = requests.post("%s/%s" % (GCS_UPLOAD, gcs_key(md5hex)), data=text.encode("utf-8"),
                          headers={"Content-Type": "application/octet-stream"}, timeout=300)
        if r.status_code == 200:
            note("  uploaded GCS blob")
        else:
            note("  WARNING: GCS upload returned %s; clients will fall back to RTDB (slower, still correct)" % r.status_code)
    except Exception as e:
        note("  WARNING: GCS upload failed (%s); clients will fall back to RTDB (slower, still correct)" % e)


# ----------------------------------------------------------------------- git
def repo_root(explicit):
    if explicit:
        return os.path.abspath(explicit)
    out = subprocess.run(["git", "-C", SCRIPT_DIR, "rev-parse", "--show-toplevel"],
                         capture_output=True, text=True)
    if out.returncode != 0:
        die("Not inside a git checkout; pass --repo <path to draw-steel-codex>.")
    return out.stdout.strip()


def git(root, *args, check=True):
    out = subprocess.run(["git", "-C", root] + list(args), capture_output=True, text=True)
    if check and out.returncode != 0:
        die("git %s failed: %s" % (" ".join(args), out.stderr.strip()))
    return out


def expand_commits(root, specs):
    shas = []
    for spec in specs:
        if ".." in spec:
            out = git(root, "rev-list", "--reverse", spec)
            shas.extend(s for s in out.stdout.split() if s)
        else:
            out = git(root, "rev-parse", "--verify", spec + "^{commit}")
            shas.append(out.stdout.strip())
    if not shas:
        die("No commits given.")
    return shas


_fetched = False


def commit_is_on_main(root, sha):
    """Name of the main ref containing sha, or None. origin/main is the authority
    (a local main can be ahead of it with unpushed work); a plain main is only
    consulted when there is no origin. Best-effort fetch first so a stale
    remote-tracking ref does not refuse a fix that was pushed a minute ago."""
    global _fetched
    if not _fetched:
        _fetched = True
        subprocess.run(["git", "-C", root, "fetch", "-q", "origin", "main"], capture_output=True, timeout=60)
    for r in ("origin/main", "main"):
        exists = subprocess.run(["git", "-C", root, "rev-parse", "--verify", "-q", r], capture_output=True)
        if exists.returncode != 0:
            continue
        anc = subprocess.run(["git", "-C", root, "merge-base", "--is-ancestor", sha, r], capture_output=True)
        return r if anc.returncode == 0 else None
    return None


def commit_files(root, sha):
    parents = git(root, "rev-list", "--parents", "-n", "1", sha).stdout.split()
    if len(parents) > 2:
        die("%s is a merge commit; hotfix the individual commits instead." % sha[:10])
    out = git(root, "diff-tree", "-r", "--no-commit-id", "--name-status", "-M", sha)
    files = []
    for line in out.stdout.splitlines():
        parts = line.split("\t")
        status = parts[0]
        path = parts[-1]
        files.append((status, path))
    return files


def git_file_at(root, rev, path):
    out = subprocess.run(["git", "-C", root, "show", "%s:%s" % (rev, path)], capture_output=True)
    if out.returncode != 0:
        die("git show %s:%s failed: %s" % (rev, path, out.stderr.decode("utf-8", "replace").strip()))
    return out.stdout.decode("utf-8")


def merge_file(current, base, other, label):
    """git merge-file: apply (base -> other) onto current. All LF. Returns text.
    Dies on conflicts, printing the conflicted text's location."""
    if current == base:
        return other
    if current == other:
        return current
    with tempfile.TemporaryDirectory() as d:
        paths = []
        for name, text in (("current", current), ("base", base), ("other", other)):
            p = os.path.join(d, name + ".lua")
            with open(p, "w", encoding="utf-8", newline="\n") as f:
                f.write(text)
            paths.append(p)
        out = subprocess.run(["git", "merge-file", "-p", "-L", "retail", "-L", "parent", "-L", "fix"] + paths,
                             capture_output=True)
        merged = out.stdout.decode("utf-8")
        if out.returncode == 0:
            return merged
        if out.returncode > 0 and "<<<<<<<" in merged:
            conflict_path = os.path.join(tempfile.gettempdir(), "dmhub-hotfix-conflict-%s.lua" % label)
            with open(conflict_path, "w", encoding="utf-8", newline="\n") as f:
                f.write(merged)
            die("%d conflict(s) merging the fix onto the retail text. The retail file has moved too\n"
                "far from the commit's parent for a clean cherry-pick. Conflicted merge written to\n"
                "  %s\n"
                "Rebase the fix onto the retail text as its own commit on main and hotfix that." % (out.returncode, conflict_path))
        die("git merge-file failed: %s" % out.stderr.decode("utf-8", "replace"))


# ---------------------------------------------------------------------- luac
def find_luac(explicit, root):
    for p in (explicit, os.environ.get("DMHUB_LUAC"),
              os.path.join(root, "..", "dependencies", "lua", "bin", "luac.exe"),
              os.path.join(root, "..", "dependencies", "lua", "bin", "luac")):
        if p and os.path.isfile(p):
            return os.path.abspath(p)
    return None


def luac_check(luac, text, label):
    """Parse-only check. Strips the engine's @if/@unless/@else/@end preprocessor
    lines first (LuaPreprocessor.cs comments them out before Lua sees them)."""
    if luac is None:
        return "skipped (no luac found; pass --luac or set $DMHUB_LUAC)"
    lines = []
    for line in to_unix(text).split("\n"):
        s = line.lstrip()
        if s.startswith("@if ") or s.startswith("@unless ") or s in ("@else", "@end"):
            line = "--" + line
        lines.append(line)
    with tempfile.TemporaryDirectory() as d:
        p = os.path.join(d, label + ".lua")
        with open(p, "w", encoding="utf-8", newline="\n") as f:
            f.write("\n".join(lines))
        out = subprocess.run([luac, "-p", p], capture_output=True, text=True)
    if out.returncode != 0:
        die("luac rejected the merged %s:\n%s" % (label, (out.stderr or out.stdout).strip()))
    return "ok"


# ----------------------------------------------------------------- analytics
def live_versions(days, exclude=()):
    """{version: set(userids)} from /AnalyticsType/gameLoaded over the last N UTC days."""
    users = collections.defaultdict(set)
    today = datetime.datetime.now(datetime.timezone.utc)
    for back in range(days):
        day = (today - datetime.timedelta(days=back)).strftime("%Y%m%d")
        data = ref("/AnalyticsType/gameLoaded/%s" % day).get() or {}
        for uid, recs in data.items():
            if uid in exclude:
                continue
            for rec in (recs or {}).values():
                v = (rec or {}).get("version")
                if v:
                    users[v].add(uid)
    return users


def print_versions(users):
    rows = sorted(users.items(), key=lambda kv: -len(kv[1]))
    total = sum(len(u) for u in users.values())
    note("%-12s %8s %6s" % ("version", "users", "share"))
    for v, u in rows:
        note("%-12s %8d %5.1f%%" % (v, len(u), 100.0 * len(u) / max(total, 1)))
    return rows


# --------------------------------------------------------------------- plan
class FilePlan(object):
    def __init__(self):
        self.mod_name = None
        self.mod_guid = None
        self.file_name = None
        self.repo_path = None
        self.file_index = -1
        self.base_index = -1
        self.base_md5 = None
        self.base_version = None
        self.hotfix_version = None
        self.insert_at = -1
        self.next_version = None
        self.crlf = False
        self.base_text = None
        self.merged_text = None
        self.new_md5 = None
        self.already_applied = False
        self.luac = None
        self.source = None


def build_plan(args):
    root = repo_root(args.repo)
    shas = expand_commits(root, args.commits)
    note("Repo: %s" % root)
    for sha in shas:
        subj = git(root, "log", "-1", "--format=%h %ad %s", "--date=short", sha).stdout.strip()
        on = commit_is_on_main(root, sha)
        note("Commit: %s  [%s]" % (subj, on or "NOT ON MAIN"))
        if on is None and not args.allow_unmerged:
            die("%s is not on origin/main or main. A hotfix must be a fix that already landed on main,\n"
                "otherwise the next regular deploy regresses it. Merge it first (or --allow-unmerged)." % sha[:10])

    # Which files, grouped by mod; the commits that touch each.
    touched = collections.OrderedDict()
    for sha in shas:
        for status, path in commit_files(root, sha):
            split = split_repo_path(path)
            if split is None:
                note("  skipping %s (not a <Mod>/<File>.lua path)" % path)
                continue
            if status[0] != "M":
                die("%s %s in %s: hotfixes can only modify existing files (no add/delete/rename)." % (status, path, sha[:10]))
            touched.setdefault(path, []).append(sha)
    if not touched:
        die("The commit(s) touch no <Mod>/<File>.lua files.")

    names = core_mod_index()
    luac = find_luac(args.luac, root)
    exclude = set(args.exclude_user or [])
    live = live_versions(args.days, exclude)
    target = args.target
    if target is None:
        if not live:
            die("No analytics found to infer the retail version; pass --target.")
        target = max(live.items(), key=lambda kv: len(kv[1]))[0]
        note("Target version (most-used in last %d days): %s" % (args.days, target))
    else:
        note("Target version: %s" % target)

    mods = {}
    plans = []
    for path, path_shas in touched.items():
        mod_name, file_name = split_repo_path(path)
        if mod_name not in names:
            die("%r is not a core mod reachable from the retail roots (path %s)." % (mod_name, path))
        guid = names[mod_name]
        if guid not in mods:
            mods[guid] = fetch_mod(guid)
        mod = mods[guid]
        fi, f = find_file(mod, file_name)
        if f is None:
            die("Mod %r has no cloud file named %r (path %s)." % (mod_name, file_name, path))
        history = f.get("history") or []
        bi = resolve_index(history, target)
        if bi < 0:
            die("No revision of %s is available to a %s client." % (path, target))
        p = FilePlan()
        p.mod_name, p.mod_guid, p.file_name, p.repo_path, p.file_index = mod_name, guid, file_name, path, fi
        p.base_index = bi
        p.base_md5 = history[bi]["md5"]
        p.base_version = entry_version(history[bi])
        p.hotfix_version = args.engine_version or p.base_version or target
        if version_gt(p.hotfix_version, target):
            die("--engine-version %s is above the target %s; the target clients would never load it." % (p.hotfix_version, target))
        if p.base_version and version_gt(p.base_version, p.hotfix_version):
            die("--engine-version %s is below the base revision's %s for %s." % (p.hotfix_version, p.base_version, path))
        p.insert_at = insert_index(history, p.hotfix_version)
        p.next_version = entry_version(history[p.insert_at]) if p.insert_at < len(history) else None

        base_text, p.source = fetch_code(p.base_md5)
        p.base_text = base_text
        p.crlf = base_text.count("\r\n") > to_unix(base_text).count("\n") // 2
        current = to_unix(base_text)
        for sha in path_shas:
            parent = to_unix(git_file_at(root, sha + "^", path))
            fixed = to_unix(git_file_at(root, sha, path))
            current = merge_file(current, parent, fixed, file_name)
        merged = current.replace("\n", "\r\n") if p.crlf else current
        p.already_applied = merged == base_text
        p.merged_text = merged
        p.new_md5 = code_md5(merged)
        p.luac = luac_check(luac, merged, file_name)
        plans.append(p)

    return root, shas, target, live, mods, plans


def reach_of(p, live):
    reached, missed = [], []
    for v in sorted(live, key=lambda v: -len(live[v])):
        ok = version_ge(v, p.hotfix_version) and (p.next_version is None or not version_ge(v, p.next_version))
        (reached if ok else missed).append(v)
    return reached, missed


def print_plan(root, shas, target, live, plans, out_dir, diff_lines):
    note()
    note("Live versions (gameLoaded, distinct users):")
    print_versions(live)
    os.makedirs(out_dir, exist_ok=True)
    for p in plans:
        note()
        note("== %s  (mod %s / %s, file #%d)" % (p.repo_path, p.mod_name, p.mod_guid, p.file_index))
        note("   base: history[%d] md5 %s engineVersion %s (fetched from %s, %s line endings)"
             % (p.base_index, p.base_md5, p.base_version or "<none>", p.source, "CRLF" if p.crlf else "LF"))
        note("   new:  md5 %s, inserted at history[%d] with engineVersion %s%s"
             % (p.new_md5, p.insert_at, p.hotfix_version,
                ", before the %s revision" % p.next_version if p.next_version else " (becomes newest)"))
        reached, missed = reach_of(p, live)
        note("   reaches clients on: %s" % (", ".join("%s (%d)" % (v, len(live[v])) for v in reached) or "none"))
        if missed:
            note("   NOT reached:        %s" % ", ".join("%s (%d)" % (v, len(live[v])) for v in missed))
        note("   luac: %s" % p.luac)
        if p.already_applied:
            note("   ALREADY APPLIED: the retail text already contains this change; nothing to do for this file.")
        merged_path = os.path.join(out_dir, p.file_name + ".lua")
        with open(merged_path, "w", encoding="utf-8", newline="") as f:
            f.write(p.merged_text)
        note("   merged file written to %s" % merged_path)
        diff = list(difflib.unified_diff(to_unix(p.base_text).split("\n"), to_unix(p.merged_text).split("\n"),
                                         "retail/" + p.repo_path, "hotfix/" + p.repo_path, lineterm="", n=3))
        note("   diff retail -> hotfix (%d lines%s):" % (len(diff), ", truncated" if len(diff) > diff_lines else ""))
        for line in diff[:diff_lines]:
            note("     " + line)
    summary = {
        "commits": shas, "target": target, "repo": root,
        "files": [{"path": p.repo_path, "mod": p.mod_guid, "baseMd5": p.base_md5, "newMd5": p.new_md5,
                   "engineVersion": p.hotfix_version, "insertAt": p.insert_at, "alreadyApplied": p.already_applied}
                  for p in plans],
    }
    with open(os.path.join(out_dir, "plan.json"), "w", encoding="utf-8") as f:
        json.dump(summary, f, indent=2)


# -------------------------------------------------------------------- apply
def apply_plan(root, shas, target, plans, args):
    todo = [p for p in plans if not p.already_applied]
    if not todo:
        note("Nothing to apply: every file already carries the fix at the target version.")
        return
    cl_guid = str(uuid.uuid4())
    short = ",".join(s[:10] for s in shas)
    comment = args.comment or git(root, "log", "-1", "--format=%s", shas[-1]).stdout.strip()
    comment = ("HOTFIX %s for %s: %s" % (short, target, comment))[:256]

    note()
    note("Uploading code...")
    for p in todo:
        note("  %s -> %s" % (p.repo_path, p.new_md5))
        upload_code(p.new_md5, p.merged_text)

    by_mod = collections.OrderedDict()
    for p in todo:
        by_mod.setdefault(p.mod_guid, []).append(p)

    note()
    for guid, mod_plans in by_mod.items():
        for attempt in range(4):
            mod, etag = fetch_mod(guid, with_etag=True)
            if mod is None:
                die("Mod %s vanished." % guid)
            changelist = {
                "timestamp": {".sv": "timestamp"},
                "guid": cl_guid,
                "userid": args.userid,
                "username": args.username,
                "comment": comment,
                "engineVersion": mod_plans[0].hotfix_version,
            }
            for p in mod_plans:
                fi, f = find_file(mod, p.file_name)
                if f is None:
                    die("File %s disappeared from mod %s." % (p.file_name, guid))
                history = f.setdefault("history", [])
                # Re-derive against the fresh record: the base must still be what we merged onto.
                bi = resolve_index(history, target)
                if bi < 0 or history[bi]["md5"] != p.base_md5:
                    die("The retail revision of %s changed under us (now %s, planned on %s). Re-run plan."
                        % (p.repo_path, history[bi]["md5"] if bi >= 0 else None, p.base_md5))
                at = insert_index(history, p.hotfix_version)
                history.insert(at, {"md5": p.new_md5, "cl": cl_guid, "engineVersion": p.hotfix_version})
                p.insert_at = at
            mod.setdefault("changelists", []).append(changelist)
            mod["updateid"] = str(uuid.uuid4())
            ok, _cur, _etag = ref("/CodeMod/%s" % guid).set_if_unchanged(etag, mod)
            if ok:
                note("Updated /CodeMod/%s (%s): %d file(s), changelist %s, updateid %s"
                     % (guid, mod_plans[0].mod_name, len(mod_plans), cl_guid, mod["updateid"]))
                break
            note("  record changed concurrently, retrying (%d)" % (attempt + 1))
        else:
            die("Could not update /CodeMod/%s after retries." % guid)

        audit = {
            "appliedAt": {".sv": "timestamp"},
            "commits": shas,
            "target": target,
            "comment": comment,
            "userid": args.userid,
            "files": [{"name": p.file_name, "path": p.repo_path, "baseMd5": p.base_md5, "newMd5": p.new_md5,
                       "engineVersion": p.hotfix_version, "insertAt": p.insert_at} for p in mod_plans],
        }
        ref("/CodeModHotfix/%s/%s" % (guid, cl_guid)).set(audit)

    note()
    note("Verifying...")
    for p in todo:
        mod = fetch_mod(p.mod_guid)
        _fi, f = find_file(mod, p.file_name)
        history = f.get("history") or []
        got = history[resolve_index(history, target)]["md5"]
        note("  %s: a %s client now resolves to %s %s" % (p.repo_path, target, got, "OK" if got == p.new_md5 else "MISMATCH"))
    note()
    note("Done. Clients pick this up the next time they load a game (SyncMod runs at login and game entry;")
    note("there is no mid-session pickup). Roll back with:")
    note("  python %s revert %s" % (os.path.basename(__file__), cl_guid))


# ------------------------------------------------------------------- revert
def cmd_revert(args):
    cl_guid = args.changelist
    found = False
    for guid in sorted(core_mod_index().values()):
        audit = ref("/CodeModHotfix/%s/%s" % (guid, cl_guid)).get()
        if audit is None and not args.scan_all:
            continue
        for attempt in range(4):
            mod, etag = fetch_mod(guid, with_etag=True)
            if mod is None:
                break
            removed = 0
            for f in mod.get("files") or []:
                hist = f.get("history") or []
                keep = [h for h in hist if h.get("cl") != cl_guid]
                removed += len(hist) - len(keep)
                f["history"] = keep
            if removed == 0:
                break
            for cl in mod.get("changelists") or []:
                if cl.get("guid") == cl_guid and not cl.get("comment", "").startswith("[REVERTED] "):
                    cl["comment"] = ("[REVERTED] " + cl.get("comment", ""))[:256]
            mod["updateid"] = str(uuid.uuid4())
            if args.dry_run:
                note("DRY RUN: would remove %d history entr%s from /CodeMod/%s (%s)" % (removed, "y" if removed == 1 else "ies", guid, mod.get("name")))
                found = True
                break
            ok, _c, _e = ref("/CodeMod/%s" % guid).set_if_unchanged(etag, mod)
            if ok:
                found = True
                note("Removed %d history entr%s from /CodeMod/%s (%s); updateid %s"
                     % (removed, "y" if removed == 1 else "ies", guid, mod.get("name"), mod["updateid"]))
                if audit is not None:
                    ref("/CodeModHotfix/%s/%s/revertedAt" % (guid, cl_guid)).set({".sv": "timestamp"})
                break
            note("  record changed concurrently, retrying (%d)" % (attempt + 1))
    if not found:
        die("No history entries carry changelist %s in any core mod (try --scan-all if it was not applied by this script)." % cl_guid)


# ------------------------------------------------------------------- status
def cmd_status(args):
    split = split_repo_path(args.path)
    if split is None:
        die("Give the file as <Mod name>/<File>.lua, e.g. 'Draw Steel Core Rules/MCDMCreature.lua'.")
    mod_name, file_name = split
    names = core_mod_index()
    if mod_name not in names:
        die("%r is not a core mod." % mod_name)
    mod = fetch_mod(names[mod_name])
    fi, f = find_file(mod, file_name)
    if f is None:
        die("No cloud file %r in %s." % (file_name, mod_name))
    history = f.get("history") or []
    cls = {c.get("guid"): c for c in mod.get("changelists") or [] if c}
    note("%s: mod %s, file #%d, %d revisions, updateid %s" % (args.path, names[mod_name], fi, len(history), mod.get("updateid")))
    note()
    note("%-5s %-34s %-10s %s" % ("idx", "md5", "engineVer", "changelist"))
    for i in range(max(0, len(history) - args.tail), len(history)):
        h = history[i]
        c = cls.get(h.get("cl"), {})
        when = c.get("timestamp")
        when = (datetime.datetime.fromtimestamp(when / 1000, datetime.timezone.utc).strftime("%Y-%m-%d")
                if isinstance(when, (int, float)) else "")
        note("%-5d %-34s %-10s %s %s %s" % (i, h.get("md5"), h.get("engineVersion") or "-", when, c.get("username", ""), (c.get("comment") or "")[:60]))
    live = live_versions(args.days, set(args.exclude_user or []))
    note()
    note("What each live version runs:")
    for v in sorted(live, key=lambda v: -len(live[v])):
        i = resolve_index(history, v)
        note("  %-10s %5d users -> history[%d] %s" % (v, len(live[v]), i, history[i]["md5"] if i >= 0 else "NOTHING"))


# --------------------------------------------------------------------- main
def add_common(sp):
    sp.add_argument("--days", type=int, default=3, help="analytics window for live versions (default 3)")
    sp.add_argument("--exclude-user", action="append", help="userid to leave out of the live-version count (repeatable)")


def add_plan_args(sp):
    sp.add_argument("commits", nargs="+", help="commit sha(s) or A..B ranges on the codex repo, oldest first")
    sp.add_argument("--target", help="retail version to patch (default: most-used version in analytics)")
    sp.add_argument("--engine-version", help="engineVersion tag for the new revision (default: the base revision's own tag, which reaches every client on that base)")
    sp.add_argument("--repo", help="path to the draw-steel-codex checkout (default: the one containing this script)")
    sp.add_argument("--luac", help="path to luac for the syntax check")
    sp.add_argument("--allow-unmerged", action="store_true", help="allow commits that are not on main (NOT recommended)")
    sp.add_argument("--out", help="directory for merged files + plan.json")
    sp.add_argument("--diff-lines", type=int, default=120)
    add_common(sp)


def main(argv=None):
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    sub = ap.add_subparsers(dest="cmd", required=True)

    s = sub.add_parser("versions", help="which app versions loaded a game recently")
    add_common(s)

    s = sub.add_parser("status", help="a file's cloud history and what each live version runs")
    s.add_argument("path", help="<Mod name>/<File>.lua")
    s.add_argument("--tail", type=int, default=8)
    add_common(s)

    s = sub.add_parser("plan", help="compute the hotfix and show it; writes nothing")
    add_plan_args(s)

    s = sub.add_parser("apply", help="compute the hotfix and ship it")
    add_plan_args(s)
    s.add_argument("--comment", help="changelist comment (default: the commit subject)")
    s.add_argument("--userid", default=os.environ.get("HOTFIX_USERID", "hotfix-script"))
    s.add_argument("--username", default=os.environ.get("HOTFIX_USERNAME", "Codex Hotfix"))

    s = sub.add_parser("revert", help="remove a hotfix's history entries again")
    s.add_argument("changelist", help="the changelist guid printed by apply")
    s.add_argument("--dry-run", action="store_true")
    s.add_argument("--scan-all", action="store_true", help="look in every core mod, not only those with an audit record")

    args = ap.parse_args(argv)
    if args.cmd == "versions":
        print_versions(live_versions(args.days, set(args.exclude_user or [])))
        return
    if args.cmd == "status":
        cmd_status(args)
        return
    if args.cmd == "revert":
        cmd_revert(args)
        return

    out_dir = args.out or os.path.join(tempfile.gettempdir(), "dmhub-hotfix",
                                       datetime.datetime.now().strftime("%Y%m%d-%H%M%S"))
    root, shas, target, live, mods, plans = build_plan(args)
    print_plan(root, shas, target, live, plans, out_dir, args.diff_lines)
    if args.cmd == "apply":
        apply_plan(root, shas, target, plans, args)


if __name__ == "__main__":
    main()
