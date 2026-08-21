"""Shared helpers for the bug-report triage pipeline.

All of the bug-report-*.py scripts import this. It centralises:
  - reaching the bug system through the internal-dashboards Worker (the
    supported path -- see "bug system API" below); this needs only the shared
    team password, and NO Firebase credential on this machine
  - loading bug-report-config.json (Discord webhooks, tag ids, dashboard url)
  - path resolution that works no matter what the current working directory is

HOW THE DATA IS REACHED. Reports live in the MCDM Realtime Database, but this
library does not talk to it. It calls /api/bugs/* on the internal-dashboards
Worker, which holds the service account as a Worker secret and exposes only the
bug system (one report by id, its issue node, its ticket marker, and a single
consent-gated chat write). The Worker enforces the consent gate itself, so it
cannot be skipped from here.

The service-account path (init_firebase/ref) is still present for the admin
tooling that shares this file, but nothing in the bug-fix skill calls it, and
firebase_admin is imported lazily so it need not even be installed.

Consumer-owned triage state lives under a single root in the MCDM RTDB:

  /BugReportTriage/issues/{threadId}   one node per distinct issue (Discord forum
                                       thread). key == the Discord thread id.
      title      : short human title (also the forum post title)
      type       : bug | feature | feedback
      signature  : short stable dedupe key the agent assigns
      status     : open | fixed | wontfix | ...  (consumer-owned)
      reportIds  : [reportId, ...] every /BugReports id folded into this issue
      channelKey : which configured Discord channel the thread lives in (see
                   resolve_channel). Absent on threads created before the
                   bug/feedback channel split -- those are all in the default
                   channel, which is exactly what the fallback assumes.
      created    : server ms
      updated    : server ms

  /BugReports/{reportId}/status        set to "triaged" once folded into an issue
  /BugReports/{reportId}/triage        { issueId: <threadId>, updated: server ms }

  /BugReportTriage/prs/{owner__repo__number}   one node per fix PR raised by a
                                       bug-fixer agent, so the merge poller
                                       (bug-report-check-prs.py) can close the
                                       issue out when the PR lands. Registered by
                                       bug-report-apply.py -- which is the only
                                       point at which both the PR and its Discord
                                       thread id are known.
      url        : the GitHub PR URL (also the source of owner/repo/number)
      repoLabel  : the fixer's repo handle ("codex" | "data")
      branch     : the triage/* branch backing the PR
      issueId    : Discord thread the fix belongs to
      reportIds  : [reportId, ...] every report the fix closes out
      state      : open | merged | closed   (closed == rejected, not merged)
      closeout   : { tickets: { <reportId>: true }, discordAt: server ms }
"""

import json
import os
import re

import requests

# firebase_admin is NOT imported at module scope. The supported path for this
# skill is the dashboard API (see "bug system API" below), which needs nothing
# but `requests`; the service-account path survives only for a caller that
# explicitly opts into it, and imports lazily inside init_firebase() so the
# package need not be installed at all.

SCRIPT_DIR = os.path.dirname(os.path.abspath(__file__))

NL = chr(10)  # so message builders need no escapes

# ---------------------------------------------------------------- credentials

# These scripts live in a source repo (draw-steel-codex), so no secret may ever
# sit next to them. Credentials live in a separate directory OUTSIDE the repo --
# the "credentials directory" -- which holds:
#
#   bug-report-config.json   optional: dashboard url, dmhubRepo, legacy keyPath
#   admin-secret.txt         (optional) release worker ADMIN_SECRET
#   admin-secret-staging.txt (optional) staging worker ADMIN_SECRET
#
# The Discord webhooks and bot token are NOT here any more -- they are Worker
# secrets on the dashboard, which performs the Discord calls itself.
#
# Resolution order, first hit wins. $BUG_REPORT_CONFIG points straight at a
# config file; $DMHUB_ADMIN_DIR names a directory holding one.
CONFIG_BASENAME = "bug-report-config.json"

CREDENTIAL_DIR_FALLBACKS = (
    os.path.join(os.path.expanduser("~"), ".dmhub"),
    os.path.join("D:", os.sep, "dev", "dmhub-admin"),
    os.path.join("C:", os.sep, "dev", "dmhub-admin"),
    os.path.join(os.path.expanduser("~"), "dev", "dmhub-admin"),
)


def config_candidates():
    """Every path a bug-report-config.json might live at, best guess first."""
    env_file = os.environ.get("BUG_REPORT_CONFIG")
    if env_file:
        yield env_file
    env_dir = os.environ.get("DMHUB_ADMIN_DIR")
    if env_dir:
        yield os.path.join(env_dir, CONFIG_BASENAME)
    for d in CREDENTIAL_DIR_FALLBACKS:
        yield os.path.join(d, CONFIG_BASENAME)
    # Last resort: next to these scripts. Only ever true for a private checkout;
    # the repo .gitignore refuses to track a real config here.
    yield os.path.join(SCRIPT_DIR, CONFIG_BASENAME)


def find_config():
    """Path of the first config that exists, or None."""
    for p in config_candidates():
        if p and os.path.isfile(p):
            return p
    return None


def credentials_dir():
    """Directory holding the resolved config -- and, by convention, the
    service-account key and any worker admin-secret files. None if unset."""
    if _config is not None:
        return _config.get("_credentialsDir")
    p = find_config()
    return os.path.dirname(os.path.abspath(p)) if p else None


def missing_config_message():
    """Only reached by a caller that explicitly demands the config file.

    Nothing in the skill does: the config is optional, and the password has its
    own (much simpler) setup path -- see missing_password_message.
    """
    lines = [
        "No %s found. It is OPTIONAL -- the skill needs only the team password" % CONFIG_BASENAME,
        "(run check-credentials.py), so you probably do not need this file at all.",
        "",
        "Looked in (first match wins):",
    ]
    for p in config_candidates():
        lines.append("  - %s" % p)
    lines += [
        "",
        "If you do want one, copy bug-report-config.example.json from",
        "  %s" % SCRIPT_DIR,
        "into %s as %s and edit it." % (CREDENTIAL_DIR_FALLBACKS[0], CONFIG_BASENAME),
        "Point elsewhere with $BUG_REPORT_CONFIG (a file) or $DMHUB_ADMIN_DIR (a directory).",
    ]
    return NL.join(lines)


_config = None
_app = None


def load_config(path=None):
    """Load bug-report-config.json from the credentials directory.

    Explicit path > $BUG_REPORT_CONFIG > $DMHUB_ADMIN_DIR > known fallbacks
    (see config_candidates). A relative keyPath resolves against the config's
    own directory, so the service-account key travels with the config instead
    of having to sit next to these scripts (which are in a git repo)."""
    global _config
    if _config is not None:
        return _config
    path = path or find_config()
    if not path or not os.path.exists(path):
        # NOT fatal any more. Reading reports and closing tickets need only the
        # dashboard password, which resolves from the environment or from
        # internal-dashboards/wrangler.jsonc -- so a machine with no config at
        # all still works for most of the skill. Only the Discord steps really
        # need this file, and they say so themselves when it is absent.
        _config = {"_missing": True, "_configPath": None, "_credentialsDir": None}
        return _config
    with open(path, "r", encoding="utf-8") as f:
        cfg = json.load(f)
    cfg["_configPath"] = os.path.abspath(path)
    cfg["_credentialsDir"] = os.path.dirname(os.path.abspath(path))
    # A relative service-account key path resolves against the config's own
    # directory first, then (legacy) against the script directory.
    key = cfg.get("keyPath", "mcdm-key.json")
    if not os.path.isabs(key):
        beside_config = os.path.join(cfg["_credentialsDir"], key)
        key = beside_config if os.path.exists(beside_config) else os.path.join(SCRIPT_DIR, key)
    cfg["keyPath"] = key
    # Deliberately NOT checked for existence here: a machine running the skill
    # is expected to have no key at all. init_firebase() is the only thing that
    # needs one, and it explains itself if it is missing.
    _config = cfg
    return cfg


def init_firebase():
    """Initialise (once) and return the firebase-admin app for the MCDM RTDB.

    LEGACY. Nothing in the bug-fix skill calls this -- the dashboard API below
    is the supported path, and it needs no key on this machine. This survives
    for admin tooling that shares this file, and fails with an explanation
    rather than a stack trace when the key or the package is absent.
    """
    global _app
    if _app is not None:
        return _app
    try:
        import firebase_admin
        from firebase_admin import credentials
    except ImportError as e:
        raise SystemExit(
            "This call wants the Firebase service-account path, which needs the\n"
            "firebase-admin package (%s). The bug-fix skill does not use it --\n"
            "it goes through the dashboard API instead. Install it only if you\n"
            "really need direct RTDB access:  pip install firebase-admin" % e
        )
    cfg = load_config()
    key = cfg.get("keyPath")
    if not key or not os.path.exists(key):
        raise SystemExit(
            "This call wants a Firebase service-account key (%s), which this\n"
            "machine does not have -- by design. The bug-fix skill reaches the\n"
            "bug system through the dashboard API instead; see CREDENTIALS.md."
            % (key or "<unset>")
        )
    _app = firebase_admin.initialize_app(
        credentials.Certificate(key),
        {"databaseURL": cfg.get("databaseURL", "https://mcdm-385cf-default-rtdb.firebaseio.com/")},
    )
    return _app


def sv_timestamp():
    """Firebase server-timestamp sentinel."""
    return {".sv": "timestamp"}


# statuses that mean a report has already been consumed and should be skipped
PROCESSED_STATUSES = {"triaged", "closed", "fixed", "wontfix", "duplicate"}

# ---------------------------------------------------------------- discord channels

DEFAULT_CHANNEL_KEY = "default"


def resolve_channel(cfg, itype):
    """Which Discord channel a NEW issue of this type opens its thread in.

    Returns {"key", "webhook", "tag"}. A Discord webhook is bound to one channel,
    so routing by type means one webhook per channel; forum tag ids are likewise
    channel-scoped, hence the tag travels with the channel rather than living in
    a single flat map.

    Config, per type (all optional -- anything unlisted uses the default channel):

      "discordWebhook": "<default channel webhook>",   # #user-feedback
      "tags": { "feature": "<tagId>", ... },            # tags in THAT channel
      "channels": {
        "bug": { "webhook": "<#bugs webhook>", "tag": "<tagId in #bugs or null>" }
      }

    `key` is the stable handle stored on the issue registry node so replies can
    find their way back to the right webhook years later; see webhook_for_key.
    """
    chan = (cfg.get("channels") or {}).get(itype)
    if isinstance(chan, dict) and chan.get("webhook"):
        return {
            "key": chan.get("key") or itype,
            "webhook": chan["webhook"],
            "tag": chan.get("tag") or None,
        }
    return {
        "key": DEFAULT_CHANNEL_KEY,
        "webhook": cfg.get("discordWebhook", ""),
        "tag": (cfg.get("tags") or {}).get(itype) or None,
    }


def webhook_for_key(cfg, key):
    """The webhook for a channel key recorded on an issue node (for replies).

    A missing/unknown key means the default channel -- which is right for every
    thread created before the split, since back then there was only one channel.
    """
    if key and key != DEFAULT_CHANNEL_KEY:
        for itype, chan in (cfg.get("channels") or {}).items():
            if not isinstance(chan, dict) or not chan.get("webhook"):
                continue
            if (chan.get("key") or itype) == key:
                return chan["webhook"]
        print("  note: unknown channelKey %r; replying via the default channel" % key)
    return cfg.get("discordWebhook", "")


def channel_is_shared(cfg, key, types):
    """True if more than one of `types` routes to this channel.

    Used to decide whether a post needs a "[BUG]"-style title prefix: in a
    channel dedicated to one type the prefix is pure noise.
    """
    return sum(1 for t in types if resolve_channel(cfg, t)["key"] == key) > 1


def ref(path):
    init_firebase()
    return db.reference(path)


# ---------------------------------------------------------------- reports

# ---------------------------------------------------------------- bug system API
#
# /api/bugs/* on the internal-dashboards Worker. The Worker holds the Firebase
# service account and exposes only the bug system; this side holds nothing but
# the shared team password. See internal-dashboards/worker/bugs.js for the
# allowlist of paths it will touch.

_report_cache = {}


class BugsClient:
    """Authenticated client for /api/bugs/*.

    Shares its login (and its cookie shape) with TicketsClient -- one password,
    one session -- so a close-out that reads a report and then posts to a ticket
    authenticates once.
    """

    def __init__(self, cfg=None, dev_name=None):
        self.cfg = cfg if cfg is not None else load_config()
        self.dev_name = dev_name or DEV_NAME_DEFAULT
        self._session = None

    def session(self):
        if self._session is not None:
            return self._session
        pw = tickets_password(self.cfg)
        if not pw:
            raise SystemExit(missing_password_message())
        s = requests.Session()
        resp = s.post("%s/api/bugs/login" % dashboard_url(self.cfg),
                      json={"name": self.dev_name, "password": pw}, timeout=30)
        if resp.status_code in (401, 403):
            raise SystemExit(
                "The dashboard rejected that password (HTTP %d)."
                "%sIt came from: %s"
                "%sCheck it against the Tickets dashboard login at %s, or ask a teammate."
                % (resp.status_code, NL, password_source(self.cfg) or "(unknown)",
                   NL, dashboard_url(self.cfg))
            )
        if resp.status_code != 200:
            raise SystemExit("Dashboard login failed (%d): %s" % (resp.status_code, resp.text[:200]))
        self._session = s
        return s

    def _url(self, sub):
        return "%s/api/bugs/%s" % (dashboard_url(self.cfg), sub)

    def get(self, sub, params=None):
        resp = self.session().get(self._url(sub), params=params or {}, timeout=30)
        if resp.status_code != 200:
            raise RuntimeError("/api/bugs/%s failed (%d): %s" % (sub, resp.status_code, resp.text[:300]))
        return resp.json()

    def post(self, sub, payload, allow_status=()):
        """POST. Statuses in allow_status come back as data rather than raising,
        so a caller can render a refusal (403 + a machine-readable code) as the
        answer it is instead of a crash."""
        resp = self.session().post(self._url(sub), json=payload, timeout=60)
        if resp.status_code == 200 or resp.status_code in allow_status:
            return resp.json() if resp.content else {}
        raise RuntimeError("/api/bugs/%s failed (%d): %s" % (sub, resp.status_code, resp.text[:300]))

    def status(self):
        return self.get("status")

    def report(self, rid):
        """{found, source, report, issue, ticket} -- cached per process, since a
        close-out asks for the same report two or three times."""
        if rid not in _report_cache:
            _report_cache[rid] = self.get("report", {"id": rid})
        return _report_cache[rid]

    def game_chat(self, rid, message, nick=None, dry_run=False, force_staging=False):
        return self.post("game-chat", {
            "reportId": rid,
            "message": message,
            "nick": nick,
            "dryRun": bool(dry_run),
            "forceStaging": bool(force_staging),
        }, allow_status=(400, 403, 404))


_bugs = None


def bugs():
    """The process-wide BugsClient (logs in once, lazily)."""
    global _bugs
    if _bugs is None:
        _bugs = BugsClient()
    return _bugs


def load_report(rid):
    """Return (source, report) for a report id, from wherever it lives.

    Novel reports are in /BugReports; processed ones have been moved to
    /BugReportsArchive by bug-report-apply.py. (None, None) if it is in neither.
    """
    data = bugs().report(rid)
    if not data.get("found"):
        return None, None
    return data.get("source"), data.get("report")


def ticket_exists(uid, rid):
    """True if this report opened a user-facing ticket.

    Only bug-type reports filed by ticket-aware clients have one, so a missing
    ticket is normal and never an error. `uid` is accepted for call
    compatibility; the server resolves the owner from the report itself.
    """
    ticket = bugs().report(rid).get("ticket") or {}
    return bool(ticket.get("exists"))


# ---------------------------------------------------------------- fix PRs

# RTDB keys may not contain . $ # [ ] or /, so a PR's identity is flattened with
# '__' rather than kept in its natural owner/repo#number spelling.
PR_URL_RE = re.compile(r"^https?://github\.com/([A-Za-z0-9_.-]+)/([A-Za-z0-9_.-]+)/pull/(\d+)")


def parse_pr_url(url):
    """Split a GitHub PR URL into {owner, repo, number}, or None if it isn't one."""
    m = PR_URL_RE.match((url or "").strip())
    if not m:
        return None
    return {"owner": m.group(1), "repo": m.group(2), "number": int(m.group(3))}


def pr_key(url):
    """The /BugReportTriage/prs key for a PR URL, or None if it is unparseable."""
    parts = parse_pr_url(url)
    return "%s__%s__%d" % (parts["owner"], parts["repo"], parts["number"]) if parts else None


def pr_label(node):
    """Human handle for a PR node: 'owner/repo#number' (falls back to the URL)."""
    if node.get("owner") and node.get("repo") and node.get("number") is not None:
        return "%s/%s#%s" % (node["owner"], node["repo"], node["number"])
    return node.get("url") or "(unknown PR)"


def record_pr(dry_run, pr, issue_id, report_ids):
    """Register a fix PR so the merge poller can close its issue out when it lands.

    `pr` is the bug-fixer agent's returned object ({url, repo, branch, summary}).
    Returns the registry key, or None if the URL is not a GitHub PR URL -- a bad
    URL must not take the surrounding apply run down, since the PR link is in the
    Discord body regardless and only the automated closeout is lost.
    """
    url = (pr or {}).get("url")
    key = pr_key(url)
    if not key:
        print("  note: %r is not a GitHub PR URL; not tracking it for merge closeout" % (url,))
        return None
    report_ids = list(report_ids or [])

    if dry_run:
        print("  [dry-run] track fix PR %s -> /BugReportTriage/prs/%s (issue %s, reports: %s)"
              % (url, key, issue_id, ", ".join(report_ids) or "-"))
        return key

    existing = ref("/BugReportTriage/prs/%s" % key).get()
    if isinstance(existing, dict):
        # Same PR seen twice (a re-run, or a second issue folded onto one fix):
        # merge the report ids but leave `state` alone, so a PR already closed
        # out is never resurrected into the poller's open set.
        merged = list(dict.fromkeys((existing.get("reportIds") or []) + report_ids))
        ref("/BugReportTriage/prs/%s/reportIds" % key).set(merged)
        return key

    parts = parse_pr_url(url)
    ref("/BugReportTriage/prs/%s" % key).set({
        "url": url,
        "owner": parts["owner"],
        "repo": parts["repo"],
        "number": parts["number"],
        "repoLabel": (pr.get("repo") or ""),
        "branch": (pr.get("branch") or ""),
        "summary": (pr.get("summary") or ""),
        "issueId": issue_id,
        "reportIds": report_ids,
        "state": "open",
        "openedAt": sv_timestamp(),
    })
    return key


# ---------------------------------------------------------------- tickets dashboard

# Team dashboard hosting the tickets UI (override via config "dashboardUrl").
DASHBOARD_URL_DEFAULT = "https://internal-dashboards.purchase-a5b.workers.dev"
DEV_NAME_DEFAULT = "Codex Developers"


def dashboard_url(cfg):
    """Base url of the internal-dashboards Worker.

    $BUG_DASHBOARD_URL overrides everything -- that is how you point the skill
    at a local `wrangler dev` (http://127.0.0.1:8787) to try a Worker change
    before deploying it.
    """
    return (os.environ.get("BUG_DASHBOARD_URL")
            or cfg.get("dashboardUrl")
            or DASHBOARD_URL_DEFAULT).rstrip("/")


def wrangler_candidates(cfg):
    """Paths where internal-dashboards/wrangler.jsonc might live, best guess first.

    A CONVENIENCE ONLY, and one that works for fewer people than it looks like:
    internal-dashboards is its own private repo, gitignored by the dmhub parent,
    so a fresh dmhub clone does not contain it. Anyone without that checkout
    supplies the password directly (see password_file_candidates).
    """
    rel = os.path.join("internal-dashboards", "wrangler.jsonc")

    env = os.environ.get("INTERNAL_DASHBOARDS_WRANGLER")
    if env:
        yield env

    configured = cfg.get("dmhubRepo")
    if configured:
        yield os.path.join(configured, rel)

    d = os.path.abspath(os.getcwd())
    while True:
        yield os.path.join(d, rel)
        parent = os.path.dirname(d)
        if parent == d:
            break
        d = parent

    yield os.path.join(SCRIPT_DIR, "..", "dmhub", rel)


# A one-line text file is the least error-prone way for a person to supply the
# password: no JSON to get wrong, it survives a new shell, and it sits outside
# every repo. This is the path the setup instructions point at.
PASSWORD_BASENAME = "tickets-password.txt"


def password_file_candidates():
    """Files that may contain nothing but the shared team password."""
    env = os.environ.get("BUG_TICKETS_PASSWORD_FILE")
    if env:
        yield env
    cdir = credentials_dir()
    if cdir:
        yield os.path.join(cdir, PASSWORD_BASENAME)
    for d in CREDENTIAL_DIR_FALLBACKS:
        yield os.path.join(d, PASSWORD_BASENAME)


def _read_password_file(path):
    """First non-blank, non-comment line, stripped. None if unusable."""
    try:
        with open(path, "r", encoding="utf-8-sig") as f:
            for line in f:
                line = line.strip()
                if line and not line.startswith("#"):
                    return line
    except OSError:
        pass
    return None


def tickets_password(cfg):
    """The shared team password gating /api/tickets/* and /api/bugs/*.

    Resolution order, first hit wins:
      1. $BUG_TICKETS_PASSWORD
      2. $BUG_TICKETS_PASSWORD_FILE, or tickets-password.txt in the credentials
         directory (~/.dmhub by default) -- the documented way to set it up
      3. "ticketsPassword" in bug-report-config.json
      4. TICKETS_PASSWORD read out of internal-dashboards/wrangler.jsonc, for
         whoever has that private repo checked out
    """
    pw = os.environ.get("BUG_TICKETS_PASSWORD")
    if pw and pw.strip():
        return pw.strip()

    for path in password_file_candidates():
        pw = _read_password_file(path)
        if pw:
            return pw

    pw = cfg.get("ticketsPassword")
    if pw and pw.strip():
        return pw.strip()

    for path in wrangler_candidates(cfg):
        try:
            with open(path, "r", encoding="utf-8") as f:
                m = re.search(r'"TICKETS_PASSWORD"\s*:\s*"([^"]*)"', f.read())
        except OSError:
            continue
        if m and m.group(1):
            return m.group(1)
    return None


def password_source(cfg):
    """Where the password came from, for reporting. Never returns the value."""
    if (os.environ.get("BUG_TICKETS_PASSWORD") or "").strip():
        return "$BUG_TICKETS_PASSWORD"
    for path in password_file_candidates():
        if _read_password_file(path):
            return path
    if (cfg.get("ticketsPassword") or "").strip():
        return "ticketsPassword in %s" % (cfg.get("_configPath") or CONFIG_BASENAME)
    for path in wrangler_candidates(cfg):
        try:
            with open(path, "r", encoding="utf-8") as f:
                if re.search(r'"TICKETS_PASSWORD"\s*:\s*"[^"]+"', f.read()):
                    return path
        except OSError:
            continue
    return None


DEFAULT_CREDENTIAL_DIR = os.path.join(os.path.expanduser("~"), ".dmhub")


def default_password_path():
    """Where the setup instructions tell a newcomer to put the password.

    Computed from the home directory rather than indexing the fallback tuple:
    this runs on the failure path, where a crash would replace the one message
    that was supposed to help.
    """
    base = CREDENTIAL_DIR_FALLBACKS[0] if CREDENTIAL_DIR_FALLBACKS else DEFAULT_CREDENTIAL_DIR
    return os.path.join(base, PASSWORD_BASENAME)


def missing_password_message():
    """Setup instructions for someone running the skill for the first time.

    Deliberately ONE obvious action -- create one file, paste one line -- with
    the alternatives listed after it for anyone who wants them. Paths are shown
    with ~ so the commands copy-paste on every platform, with the resolved
    location underneath so there is no doubt where it lands.
    """
    return NL.join([
        "The bug-fix tools need the shared team password, and cannot find one.",
        "",
        "Put it on a single line in:",
        "",
        "    ~/.dmhub/" + PASSWORD_BASENAME,
        "    (on this machine: %s)" % default_password_path(),
        "",
        "Create it with an editor, or:",
        "",
        "    mkdir -p ~/.dmhub",
        "    printf '%s' 'THE-PASSWORD' > ~/.dmhub/" + PASSWORD_BASENAME,
        "",
        "(an editor keeps it out of your shell history).",
        "",
        "It is the same password as the Tickets dashboard login at",
        "%s -- ask a teammate for it." % DASHBOARD_URL_DEFAULT,
        "",
        "That is the whole setup: the dashboard holds every other credential.",
        "",
        "Alternatives: $BUG_TICKETS_PASSWORD, or $BUG_TICKETS_PASSWORD_FILE",
        'pointing at a file elsewhere, or "ticketsPassword" in %s.' % CONFIG_BASENAME,
    ])


class TicketsClient:
    """Authenticated client for the dashboard's /api/tickets/* endpoints.

    Logs in lazily and exactly once, so closing out a dozen reports costs one
    login -- and a run that turns out to have nothing to post costs none, which
    also means a missing password only becomes fatal if a ticket is really there
    to update.

    Failure modes are deliberately different: a missing password or a rejected
    login is a configuration fault that invalidates the whole run and raises
    SystemExit, while a single failed request raises RuntimeError so a caller
    looping over many reports can record that one as failed and keep going.
    """

    def __init__(self, cfg, dev_name=None):
        self.cfg = cfg
        self.dev_name = dev_name or DEV_NAME_DEFAULT
        self._session = None

    def session(self):
        if self._session is not None:
            return self._session
        pw = tickets_password(self.cfg)
        if not pw:
            raise SystemExit(missing_password_message())
        s = requests.Session()
        resp = s.post(
            "%s/api/tickets/login" % dashboard_url(self.cfg),
            json={"name": self.dev_name, "password": pw},
            timeout=30,
        )
        if resp.status_code != 200:
            raise SystemExit("Dashboard login failed (%d): %s" % (resp.status_code, resp.text[:200]))
        self._session = s
        return s

    def _post(self, sub, payload):
        resp = self.session().post(
            "%s/api/tickets/%s" % (dashboard_url(self.cfg), sub), json=payload, timeout=30)
        if resp.status_code != 200:
            raise RuntimeError("/api/tickets/%s failed (%d): %s"
                               % (sub, resp.status_code, resp.text[:200]))
        return resp.json() if resp.content else {}

    def message(self, uid, rid, text):
        """Post a developer message, which bumps the ticket's lastDevMessageAt."""
        return self._post("message", {"uid": uid, "id": rid, "text": text})

    def close(self, uid, rid):
        return self._post("status", {"uid": uid, "id": rid, "status": "closed"})


# ---------------------------------------------------------------- discord replies

DISCORD_COLOR_RESOLVED = 0x2ECC71  # green: resolved


def discord_reply(cfg, thread_id, text, color=DISCORD_COLOR_RESOLVED, channel_key=None):
    """Reply into an existing forum thread, through the dashboard.

    The Worker holds the webhooks and picks the right one from the thread's own
    issue node -- bugs and other feedback live in different forums, and a
    webhook is bound to one channel. `channel_key` is accepted for call
    compatibility and ignored: letting the caller name the channel would let it
    post into the wrong forum, so the server resolves it.

    Raises SystemExit when Discord is not configured on the Worker, matching the
    old behaviour of a missing webhook in the local config.
    """
    out = bugs().post("discord-reply", {
        "threadId": thread_id,
        "text": text,
        "color": color,
    }, allow_status=(400, 502))
    if not out.get("ok"):
        if out.get("code") == "no-webhook":
            raise SystemExit(
                "No Discord webhook is configured on the dashboard. Set it with:"
                "\n  cd internal-dashboards"
                "\n  npx wrangler secret put DISCORD_WEBHOOKS"
                '\n(the value is a JSON map, e.g.'
                ' {"default":"https://...","bug":"https://..."})'
            )
        raise SystemExit("Discord reply failed: %s" % out.get("error", out))
    return out


# ---------------------------------------------------------------- discord threads

def discord_bot_token(cfg):
    """Truthy when the DASHBOARD has a bot token, i.e. archiving can work.

    Everything else in this pipeline posts through a webhook, but a webhook
    token only authorises /webhooks/{id}/{token} message endpoints -- it cannot
    touch /channels/{id}, where thread state lives. Archiving therefore needs a
    real bot in the guild with Manage Threads on the forum channels (the threads
    are owned by the webhook, not the bot, so thread-owner archive rights do not
    apply).

    The token itself never comes over the wire -- this reports only whether one
    is configured, so a caller can skip the archive step with a useful message.
    Absent is a supported state.
    """
    try:
        return bool((bugs().status().get("discord") or {}).get("botToken"))
    except Exception:
        return False


def discord_archive_thread(cfg, thread_id):
    """Archive a forum thread, through the dashboard. Returns (ok, detail);
    never raises for the caller.

    Archive only, deliberately not locked: a reporter who answers "still broken"
    into an archived thread un-archives it by doing so, which is a free reopen
    signal we would throw away by locking.

    Call this AFTER posting the closing reply -- posting into an archived thread
    is what would un-archive it again.
    """
    try:
        out = bugs().post("discord-archive", {"threadId": thread_id},
                          allow_status=(400, 502))
    except Exception as e:
        return (False, str(e))
    if out.get("ok") and out.get("archived"):
        return (True, out.get("detail") or "archived thread %s" % thread_id)
    if out.get("ok"):
        # No bot token on the Worker: tidying was skipped, the closeout was not.
        return (None, out.get("detail") or "no bot token configured -- thread left open")
    return (False, out.get("error") or "archive failed")
