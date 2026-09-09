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
by other means. NOTE: this form is DurableObjects-only. The dashboard API acts
only on a report (there is nothing to check consent against otherwise), so this
path never reaches Firebase and cannot read /games to pick a worker -- name the
staging one with --staging, or take the release default.

WHERE THE WORK HAPPENS. With --report, the internal-dashboards Worker does the
report lookup, the consent gate and the backend routing, and performs the write
itself for a Firebase-backed game -- this script holds no Firebase credential.
The gate therefore lives on the far side of the team password and cannot be
skipped from here.

Backends (routed by the Worker from /games/{gameid}/storage):
  - Firebase (storage 0 / absent)      -> the Worker writes
                                          /GameDetails/{gameid}/chat/{guid}
  - DurableObjects (storage 1)         -> Worker authorises; THIS script makes
                                          the admin WebSocket put (release)
  - DurableObjectsStaging (storage 2)  -> same, against the staging worker
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

Dependencies: `requests` (via bugreport_lib, for the dashboard API) and the
`websockets` package for the DO path (import guarded). No firebase-admin, and
no service-account key on this machine.

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

# Backend names as the dashboard API reports them (bugs.js keeps the
# StorageBackend enum mapping now -- AccountInfo.cs:432 is its source).
BACKEND_FIREBASE = "firebase"
BACKEND_DO_RELEASE = "durableobjects"
BACKEND_DO_STAGING = "durableobjectsstaging"
BACKEND_LOCAL = "local"


def die(msg, code=1):
    print("ERROR: " + msg, file=sys.stderr)
    sys.exit(code)


# -- Dashboard (holds the Firebase credential) --------------------------------

def _lib():
    """Lazily import bugreport_lib, which carries the /api/bugs/* client.

    The report lookup, the consent gate, the backend routing and the Firebase
    write all happen in the Worker now -- this script no longer has, or needs,
    a Firebase credential. What stays here is the DurableObjects path: that
    needs an admin WebSocket to the game-server Worker with its own
    ADMIN_SECRET, which the dashboard has no business holding."""
    try:
        import bugreport_lib  # noqa
    except Exception as e:
        die("could not import bugreport_lib (needed for the dashboard API): %s" % e)
    return bugreport_lib


# -- Send paths ---------------------------------------------------------------

def build_record(nick, message):
    """The chat record, for the --game path only (the --report path gets the
    record back from the Worker, which builds the identical thing).

    `{".sv":"timestamp"}` is Firebase's server-timestamp placeholder; it is
    resolved server-side on BOTH backends -- the RTDB REST layer resolves it
    natively, and the DO worker's handlePut runs data through
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

    # -- The --report path: the Worker decides, and does the Firebase half ----
    #
    # It loads the report, applies the consent gate (allowGameEntry / isLobby /
    # Local), resolves the backend from /games, and -- for a Firebase game --
    # performs the write. That is deliberately not negotiable from here: the
    # gate now lives on the server side of the password, so this script cannot
    # talk its way past it.
    if args.report:
        lib = _lib()
        result = lib.bugs().game_chat(
            args.report, message,
            nick=args.nick, dry_run=args.dry_run, force_staging=args.staging,
        )
        if not result.get("ok"):
            die("%s (%s)" % (result.get("error", "refused"), result.get("code", "?")))

        plan = result["plan"]
        print("[report] found in %s" % plan.get("reportSource"), flush=True)
        print("[plan] game=%s storage=%r backend=%s"
              % (plan["gameid"], plan.get("storage"), plan["backend"]), flush=True)
        print("[plan] record: %s" % json.dumps(plan["record"], ensure_ascii=False), flush=True)

        if result.get("dryRun"):
            print("[plan] target: %s" % _describe_target(plan), flush=True)
            print("[dry-run] no connection made, nothing written.", flush=True)
            return

        if result.get("sent"):
            print("[done] chat message written to %s via the dashboard "
                  "(guid=%s)." % (plan["gameid"], plan["guid"]), flush=True)
            return

        # Delegated: a DurableObjects game. The Worker resolved and authorised
        # it; the admin WebSocket write is ours to make.
        staging = (plan["backend"] == BACKEND_DO_STAGING)
        print("[plan] target: %s" % _describe_target(plan), flush=True)
        secret = load_admin_secret(args.admin_secret, staging)
        send_durable_object(plan["gameid"], plan["guid"], plan["record"], staging, secret)
        print("[done] chat message sent to %s as %r (guid=%s)."
              % (plan["gameid"], plan["record"].get("nick"), plan["guid"]), flush=True)
        return

    # -- The --game escape hatch: no report, so no consent to check -----------
    #
    # The dashboard API refuses to take a bare gameid (there is nothing to check
    # consent against), so this path never reaches Firebase -- which makes it
    # DurableObjects-only, and it cannot read /games to work out which worker.
    # Say which one with --staging, or accept the release default.
    gameid = args.game
    print("WARNING: --no-report-check: allowGameEntry was NOT verified. "
          "Only proceed if you have the user's consent by other means.",
          file=sys.stderr)
    print("WARNING: without a report this cannot reach a Firebase-backed game "
          "(the dashboard API only acts on a report). Assuming a DurableObjects "
          "game on the %s worker." % ("staging" if args.staging else "release"),
          file=sys.stderr)

    guid = str(uuid.uuid4())
    record = build_record(args.nick, message)
    ws_url = (STAGING_WS if args.staging else RELEASE_WS).format(gameid=gameid)
    print("[plan] game=%s backend=%s" % (gameid, "durableobjects"), flush=True)
    print("[plan] target: DO admin put %s  store=game path=/chat/%s" % (ws_url, guid), flush=True)
    print("[plan] record: %s" % json.dumps(record, ensure_ascii=False), flush=True)

    if args.dry_run:
        print("[dry-run] no connection made, nothing written.", flush=True)
        return

    secret = load_admin_secret(args.admin_secret, args.staging)
    send_durable_object(gameid, guid, record, args.staging, secret)
    print("[done] chat message sent to %s as %r (guid=%s)."
          % (gameid, args.nick, guid), flush=True)


def _describe_target(plan):
    """Human-readable destination for the plan the Worker resolved."""
    if plan["backend"] == BACKEND_FIREBASE:
        return "Firebase RTDB set %s (written by the dashboard)" % plan["path"]
    staging = (plan["backend"] == BACKEND_DO_STAGING)
    ws_url = (STAGING_WS if staging else RELEASE_WS).format(gameid=plan["gameid"])
    return "DO admin put %s  store=game path=/chat/%s" % (ws_url, plan["guid"])


if __name__ == "__main__":
    try:
        main()
    except KeyboardInterrupt:
        print("\ninterrupted", file=sys.stderr)
        sys.exit(130)
