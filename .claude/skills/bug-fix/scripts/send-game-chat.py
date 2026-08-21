#!/usr/bin/env python3
"""
send-game-chat.py -- Post a chat message into a user's DMHub game as "Codex Team".

Primary use: notify a bug reporter, IN THEIR GAME, that their issue was fixed
(or their data was repaired). The message appears in the game's chat log as a
normal message from "Codex Team".

    python send-game-chat.py --report <reportId> "We fixed the token-vanish bug
        you reported (-Ow...); the fix ships in the next release. -- Codex Team"

CONSENT GATE (--report flow): the script REFUSES to send unless the report has
`allowGameEntry: true`. That flag is the user's explicit grant for us to enter
their game -- it is what authorizes writing a chat line into it. It also refuses
for lobby reports (`isLobby: true`) and for games whose storage backend is
`Local`, both of which are unreachable from our side.

    python send-game-chat.py --game <gameid> --no-report-check "<message>"

The --game/--no-report-check form bypasses the report lookup for non-bug-report
uses (e.g. a manual note into a known game). It prints a warning that
allowGameEntry was NOT verified -- use it only when you have the user's consent
by other means.

Backends (routed automatically from /games/{gameid}/storage in Firebase MCDM):
  - Firebase (storage 0 / absent)      -> service-account write to
                                          /GameDetails/{gameid}/chat/{guid}
  - DurableObjects (storage 1)         -> admin WebSocket put to release worker
  - DurableObjectsStaging (storage 2)  -> admin WebSocket put to staging worker
  - Local (storage 3)                  -> refused (unreachable)

ADMIN SECRET (only needed for DurableObjects games):
  A DO admin WebSocket connection authenticates with the worker's shared
  ADMIN_SECRET (see cloudflare-game-server/src/admin-auth.ts + handleAuth in
  index.ts). Wrangler secrets can't be read back, so this script sources the
  value, in order, from:
    1. --admin-secret <value> on the command line
    2. env var DMHUB_ADMIN_SECRET  (release)  /  DMHUB_ADMIN_SECRET_STAGING (staging)
    3. a file in the CREDENTIALS DIRECTORY (the directory holding
       bug-report-config.json -- see bugreport_lib.credentials_dir):
         release: admin-secret.txt, then MCDM_CLOUDFLARE_SECRET.txt
         staging: admin-secret-staging.txt
  This script lives in a git repo, so the secret must NOT be placed next to it.
  To (re)establish the value: `wrangler secret put ADMIN_SECRET` (release) /
  `wrangler secret put ADMIN_SECRET --env staging`, then save the same value
  into the file above. Wrangler cannot read a secret back.

Dependencies: firebase-admin (already used across dmhub-admin) for Firebase
reads/writes, and the `websockets` package for the DO path (import guarded).

Dry run: --dry-run prints the resolved backend, target URL/path, and the exact
record JSON, and writes nothing.
"""

import argparse
import json
import os
import sys
import time
import uuid

# Windows consoles default to cp1252, but report text is arbitrary user content
# (emoji, narrow no-break spaces, em dashes). Without this, a write dies mid-stream
# with UnicodeEncodeError and truncates the output -- silently, when redirected.
for _stream in (sys.stdout, sys.stderr):
    try:
        _stream.reconfigure(encoding="utf-8")
    except (AttributeError, ValueError):
        pass


# On Windows the default stdout encoding is cp1252, which chokes on any
# non-ASCII character a message might contain. Reconfigure to UTF-8 so log
# lines (and echoed message text) always print. Python 3.7+. Matches
# migrate-game-to-do.py.
try:
    sys.stdout.reconfigure(encoding="utf-8")
    sys.stderr.reconfigure(encoding="utf-8")
except AttributeError:
    pass

SCRIPT_DIR = os.path.dirname(os.path.abspath(__file__))

# Cloudflare game-server WebSocket endpoints. codexback.com is the current
# host (the legacy purchase-a5b.workers.dev also still resolves).
RELEASE_WS = "wss://game-server.codexback.com/game/{gameid}"
STAGING_WS = "wss://game-server-staging.codexback.com/game/{gameid}"

# Cloudflare's WAF blocks the default "Python-*" User-Agent on some paths;
# send a plain UA on the WS upgrade to be safe (mirrors report-do.py).
HTTP_USER_AGENT = "dmhub-admin-send-game-chat/1.0"

# Fixed identity of the sender. The chat panel renders `nick`, not `userid`,
# so an unknown userid renders fine; a distinctive userid keeps these lines
# attributable/greppable in the game data.
SENDER_USERID = "codex-team"
DEFAULT_NICK = "Codex Team"

# StorageBackend enum (AccountInfo.cs:432). /games/{gameid}/storage is written
# as this int (absent == 0 == Firebase); reports carry it as a string.
BACKEND_FIREBASE = "firebase"
BACKEND_DO_RELEASE = "durableobjects"
BACKEND_DO_STAGING = "durableobjectsstaging"
BACKEND_LOCAL = "local"

_INT_TO_BACKEND = {
    0: BACKEND_FIREBASE,
    1: BACKEND_DO_RELEASE,
    2: BACKEND_DO_STAGING,
    3: BACKEND_LOCAL,
}
_STR_TO_BACKEND = {
    "firebase": BACKEND_FIREBASE,
    "durableobjects": BACKEND_DO_RELEASE,
    "durableobjectsstaging": BACKEND_DO_STAGING,
    "local": BACKEND_LOCAL,
}


def die(msg, code=1):
    print("ERROR: " + msg, file=sys.stderr)
    sys.exit(code)


# -- Firebase reads (reuse bugreport_lib's service-account app) --------------

def _lib():
    """Lazily import bugreport_lib (initialises firebase-admin against the
    MCDM RTDB with mcdm-key.json). Its .ref() authenticates with the service
    account -- an OAuth Bearer token that bypasses RTDB security rules, which
    is exactly the privileged write path we want (no ?auth=)."""
    try:
        import bugreport_lib  # noqa
    except Exception as e:
        die("could not import bugreport_lib (needed for Firebase access): %s" % e)
    return bugreport_lib


def fetch_report(report_id):
    """Return (source, report) from /BugReports then /BugReportsArchive, or
    (None, None). Mirrors bug-report-get.py."""
    lib = _lib()
    r = lib.ref("/BugReports/%s" % report_id).get()
    if isinstance(r, dict):
        return "BugReports", r
    r = lib.ref("/BugReportsArchive/%s" % report_id).get()
    if isinstance(r, dict):
        return "BugReportsArchive", r
    return None, None


def resolve_backend(gameid, force_staging):
    """Read /games/{gameid}/storage and map it to a backend constant.
    Returns (backend, raw_storage_value). Missing game -> (None, None)."""
    lib = _lib()
    games_node = lib.ref("/games/%s" % gameid).get()
    if not isinstance(games_node, dict):
        return None, None
    raw = games_node.get("storage")
    backend = None
    if raw is None:
        backend = BACKEND_FIREBASE
    elif isinstance(raw, bool):
        # Defensive: a bool would be a data error; treat as Firebase default.
        backend = BACKEND_FIREBASE
    elif isinstance(raw, int):
        backend = _INT_TO_BACKEND.get(raw)
    elif isinstance(raw, str):
        backend = _STR_TO_BACKEND.get(raw.strip().lower())
    if backend is None:
        die("unrecognised storage value %r at /games/%s/storage" % (raw, gameid))
    # --staging forces DO writes at the staging worker regardless of which DO
    # the game is flagged for. Only meaningful for DO backends.
    if force_staging and backend in (BACKEND_DO_RELEASE, BACKEND_DO_STAGING):
        backend = BACKEND_DO_STAGING
    return backend, raw


# -- Send paths ---------------------------------------------------------------

def build_record(nick, message):
    """The chat record. `{".sv":"timestamp"}` is Firebase's server-timestamp
    placeholder; it is resolved server-side on BOTH backends -- the RTDB REST
    layer resolves it natively, and the DO worker's handlePut runs data through
    normalizeForFirebaseCompat (json-patch.ts:82, index.ts:5397), which turns
    it into Date.now(). No nickColor is set: the chat panel treats an alpha<0.9
    nickColor as "use a default light color" (ChatPanel.lua FormatChatMessage),
    so the line renders as a light-tinted "<nick>: <message>"."""
    return {
        "userid": SENDER_USERID,
        "nick": nick,
        "message": message,
        "timestamp": {".sv": "timestamp"},
    }


def send_firebase(gameid, guid, record):
    lib = _lib()
    path = "/GameDetails/%s/chat/%s" % (gameid, guid)
    # set() writes the whole (new) record; the service account bypasses rules.
    lib.ref(path).set(record)


def load_admin_secret(cli_secret, staging):
    if cli_secret:
        return cli_secret.strip()
    env_name = "DMHUB_ADMIN_SECRET_STAGING" if staging else "DMHUB_ADMIN_SECRET"
    val = os.environ.get(env_name)
    if val and val.strip():
        return val.strip()
    if staging:
        candidates = ["admin-secret-staging.txt"]
    else:
        candidates = ["admin-secret.txt", "MCDM_CLOUDFLARE_SECRET.txt"]
    # The credentials directory (where bug-report-config.json lives) is the
    # right home for this; SCRIPT_DIR is a git repo and must never hold a
    # secret. SCRIPT_DIR stays in the list only for legacy private checkouts.
    dirs = []
    try:
        cdir = _lib().credentials_dir()
        if cdir:
            dirs.append(cdir)
    except SystemExit:
        pass
    dirs.append(SCRIPT_DIR)
    for d in dirs:
        for name in candidates:
            path = os.path.join(d, name)
            if os.path.isfile(path):
                with open(path, "r", encoding="utf-8") as f:
                    val = f.read().strip()
                if val:
                    print("[admin-secret] using %s" % path, flush=True)
                    return val
    die(
        "no admin secret found for the %s worker. Provide one via "
        "--admin-secret, env %s, or a file (%s) in the credentials directory "
        "(%s). The value is whatever was set via `wrangler secret put "
        "ADMIN_SECRET`; it cannot be read back from wrangler."
        % ("staging" if staging else "release", env_name, ", ".join(candidates),
           dirs[0])
    )


def send_durable_object(gameid, guid, record, staging, admin_secret, timeout=15.0):
    try:
        from websockets.sync.client import connect
    except Exception:
        die(
            "the `websockets` package is required for DurableObjects games "
            "but is not importable. Install it: pip install websockets"
        )

    url = (STAGING_WS if staging else RELEASE_WS).format(gameid=gameid)
    put_req_id = "sendchat-" + guid

    print("[do] connecting to %s" % url, flush=True)
    deadline = time.time() + timeout
    with connect(
        url,
        additional_headers={"User-Agent": HTTP_USER_AGENT},
        open_timeout=timeout,
        close_timeout=5,
    ) as ws:
        # 1. Authenticate as admin. userId is a free-form audit label.
        ws.send(json.dumps({
            "type": "auth",
            "adminSecret": admin_secret,
            "userId": SENDER_USERID,
        }))
        _wait_for_ack(ws, "auth", deadline, what="admin auth")

        # 2. Put the chat record. store defaults to "game"; path is the message
        #    node under /chat. handlePut resolves the .sv timestamp.
        ws.send(json.dumps({
            "type": "put",
            "store": "game",
            "path": "/chat/%s" % guid,
            "data": record,
            "reqId": put_req_id,
        }))
        _wait_for_ack(ws, put_req_id, deadline, what="chat put")


def _wait_for_ack(ws, req_id, deadline, what):
    """Read messages until we see {type:"ack", reqId:req_id}. Other messages
    (e.g. the initial full-store `put` the server pushes on connect) are
    skipped. Raises on ok:false or timeout."""
    while True:
        remaining = deadline - time.time()
        if remaining <= 0:
            die("timed out waiting for %s ack (reqId=%s)" % (what, req_id))
        try:
            raw = ws.recv(timeout=remaining)
        except TimeoutError:
            die("timed out waiting for %s ack (reqId=%s)" % (what, req_id))
        try:
            msg = json.loads(raw)
        except (ValueError, TypeError):
            continue
        if msg.get("type") == "ack" and msg.get("reqId") == req_id:
            if msg.get("ok"):
                return msg
            die("%s failed: %s" % (what, msg.get("error", "ack ok:false")))
        if msg.get("type") == "error":
            die("%s: server error: %s" % (what, msg.get("message", "?")))


# -- Main ---------------------------------------------------------------------

def _normalize_argv(argv):
    """Firebase push ids (and thus report ids) start with '-', which argparse
    would treat as an option in the `--report -Oxxx` space form. Rewrite the
    known value-taking options to their `--opt=value` form so both spellings
    work. Only rewrites when the following token is present and the option is
    the bare long form (an explicit `--opt=...` is left untouched)."""
    value_opts = ("--report", "--game", "--nick", "--admin-secret")
    out = []
    i = 0
    while i < len(argv):
        tok = argv[i]
        if tok in value_opts and i + 1 < len(argv):
            out.append("%s=%s" % (tok, argv[i + 1]))
            i += 2
            continue
        out.append(tok)
        i += 1
    return out


def main():
    sys.argv = [sys.argv[0]] + _normalize_argv(sys.argv[1:])
    p = argparse.ArgumentParser(
        description="Send a 'Codex Team' chat message into a user's DMHub game.",
        formatter_class=argparse.RawDescriptionHelpFormatter,
    )
    p.add_argument("message", help="The chat message text to send.")
    src = p.add_mutually_exclusive_group(required=True)
    src.add_argument("--report", metavar="REPORTID",
                     help="Bug report id; derives the gameid and enforces the "
                          "allowGameEntry consent gate.")
    src.add_argument("--game", metavar="GAMEID",
                     help="Target gameid directly (requires --no-report-check).")
    p.add_argument("--no-report-check", action="store_true",
                   help="With --game: skip the report/consent lookup. Prints a "
                        "warning that allowGameEntry was not verified.")
    p.add_argument("--nick", default=DEFAULT_NICK,
                   help="Display name for the sender (default: %r)." % DEFAULT_NICK)
    p.add_argument("--staging", action="store_true",
                   help="Force DO writes at the staging worker (override). "
                        "Normally the worker is chosen from /games storage.")
    p.add_argument("--admin-secret", default=None,
                   help="ADMIN_SECRET for DO worker admin auth (else env/file).")
    p.add_argument("--dry-run", action="store_true",
                   help="Print the resolved backend, target, and record JSON; "
                        "connect to nothing and write nothing.")
    args = p.parse_args()

    if args.game and not args.no_report_check:
        die("--game requires --no-report-check (there is no consent gate "
            "without a report; pass it to acknowledge that).")

    message = args.message
    if not message or not message.strip():
        die("message is empty.")

    # -- Resolve the target game + consent -----------------------------------
    if args.report:
        source, report = fetch_report(args.report)
        if report is None:
            die("report %s not found in /BugReports or /BugReportsArchive "
                "(check for a typo)." % args.report)
        print("[report] found in %s" % source, flush=True)

        gameid = report.get("gameid")
        if not gameid:
            die("report %s has no gameid (no game was loaded when it was "
                "filed) -- nothing to send into." % args.report)

        if report.get("isLobby") is True:
            die("report %s was filed from the local lobby (isLobby=true); the "
                "lobby game is on the user's machine and is unreachable." % args.report)

        if report.get("allowGameEntry") is not True:
            die("report %s does not grant allowGameEntry (it is %r). This is "
                "the consent gate -- refuse to write into the game without it."
                % (args.report, report.get("allowGameEntry")))
    else:
        gameid = args.game
        report = None
        print("WARNING: --no-report-check: allowGameEntry was NOT verified. "
              "Only proceed if you have the user's consent by other means.",
              file=sys.stderr)

    backend, raw_storage = resolve_backend(gameid, args.staging)
    if backend is None:
        die("game %s not found at /games/%s in Firebase -- it may be a Local/"
            "lobby game or have been deleted; unreachable." % (gameid, gameid))
    if backend == BACKEND_LOCAL:
        die("game %s uses the Local storage backend (per-machine lobby server); "
            "it is unreachable from here." % gameid)

    guid = str(uuid.uuid4())
    record = build_record(args.nick, message)

    # Resolve the concrete target for logging / dry-run.
    if backend == BACKEND_FIREBASE:
        target = "Firebase RTDB set /GameDetails/%s/chat/%s" % (gameid, guid)
    else:
        staging = (backend == BACKEND_DO_STAGING)
        ws_url = (STAGING_WS if staging else RELEASE_WS).format(gameid=gameid)
        target = "DO admin put %s  store=game path=/chat/%s" % (ws_url, guid)

    print("[plan] game=%s storage=%r backend=%s" % (gameid, raw_storage, backend), flush=True)
    print("[plan] target: %s" % target, flush=True)
    print("[plan] record: %s" % json.dumps(record, ensure_ascii=False), flush=True)

    if args.dry_run:
        print("[dry-run] no connection made, nothing written.", flush=True)
        return

    if backend == BACKEND_FIREBASE:
        send_firebase(gameid, guid, record)
    else:
        staging = (backend == BACKEND_DO_STAGING)
        secret = load_admin_secret(args.admin_secret, staging)
        send_durable_object(gameid, guid, record, staging, secret)

    print("[done] chat message sent to %s as %r (guid=%s)."
          % (gameid, args.nick, guid), flush=True)


if __name__ == "__main__":
    try:
        main()
    except KeyboardInterrupt:
        print("\ninterrupted", file=sys.stderr)
        sys.exit(130)
