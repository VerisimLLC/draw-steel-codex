"""Report which bug-fix credentials are configured, and how to supply the rest.

Run this before anything else when a bug-fix step fails with a credentials
error, or when setting the skill up on a new machine:

    python check-credentials.py

It never prints a secret -- only whether one resolved, and from where. Exit
code 0 if the core (Firebase) credentials are usable, 1 if not; optional
credentials that are missing are reported as such but do not fail the run.

The five credentials, and what each unlocks:

  1. Firebase service-account key (mcdm-key.json)   REQUIRED for everything
  2. Discord webhook(s)                             closeout step 3
  3. Discord bot token                              closeout step 4 (archive)
  4. Dashboard tickets password                     closeout steps 1+2
  5. Worker ADMIN_SECRET                            send-game-chat to a DO game

See CREDENTIALS.md next to this script for how to obtain each one.
"""

import os
import sys

SCRIPT_DIR = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, SCRIPT_DIR)

# Windows consoles default to cp1252, but report text is arbitrary user content
# (emoji, narrow no-break spaces, em dashes). Without this, a write dies mid-stream
# with UnicodeEncodeError and truncates the output -- silently, when redirected.
for _stream in (sys.stdout, sys.stderr):
    try:
        _stream.reconfigure(encoding="utf-8")
    except (AttributeError, ValueError):
        pass



def line(ok, label, detail):
    mark = "[ok]  " if ok is True else ("[--]  " if ok is None else "[MISSING] ")
    print("%s%s" % (mark.ljust(11), label))
    for d in detail:
        print("           %s" % d)


def main():
    try:
        import bugreport_lib as lib
    except Exception as e:
        print("Cannot import bugreport_lib: %s" % e)
        print("Install the dependencies first:  pip install -r %s"
              % os.path.join(SCRIPT_DIR, "requirements.txt"))
        return 1

    print("bug-fix credentials check")
    print("scripts:  %s" % SCRIPT_DIR)
    print("")

    cfg_path = lib.find_config()
    if not cfg_path:
        print(lib.missing_config_message())
        return 1

    cdir = os.path.dirname(cfg_path)
    print("config:   %s" % cfg_path)
    print("creds dir:%s" % (" " + cdir))
    print("")

    ok = True

    # 1 -- Firebase service account. Everything reads /BugReports through it.
    try:
        cfg = lib.load_config()
    except SystemExit as e:
        print(str(e))
        return 1
    key = cfg.get("keyPath")
    try:
        lib.init_firebase()
        probe = lib.ref("/BugReports").get(shallow=True)
        count = len(probe) if isinstance(probe, dict) else 0
        line(True, "Firebase service-account key (REQUIRED)",
             ["key:  %s" % key,
              "RTDB: %s" % cfg.get("databaseURL", "?"),
              "connected; /BugReports holds %d un-triaged report(s)" % count])
    except Exception as e:
        ok = False
        line(False, "Firebase service-account key (REQUIRED)",
             ["key:  %s" % key,
              "error: %s" % e,
              "Firebase console (project mcdm-385cf) > Project settings >",
              "Service accounts > Generate new private key; save it there."])

    # 2 -- Discord webhooks. Closeout step 3 posts the 'Fixed and Closed' reply.
    hooks = []
    if cfg.get("discordWebhook"):
        hooks.append("default")
    for k in (cfg.get("channels") or {}):
        if (cfg["channels"][k] or {}).get("webhook"):
            hooks.append(k)
    placeholder = "REPLACE_ME" in str(cfg.get("discordWebhook", ""))
    if hooks and not placeholder:
        line(True, "Discord webhook(s) -- closeout: reply to the thread",
             ["channels configured: %s" % ", ".join(hooks)])
    else:
        line(False, "Discord webhook(s) -- closeout: reply to the thread",
             ["set 'discordWebhook' (and optionally 'channels') in the config",
              "Discord: channel > Edit Channel > Integrations > Webhooks"])

    # 3 -- Discord bot token. ONLY archives the thread; absence is not fatal.
    token = os.environ.get("DISCORD_BOT_TOKEN") or cfg.get("discordBotToken")
    if token:
        line(True, "Discord bot token -- closeout: archive the thread",
             ["source: %s" % ("$DISCORD_BOT_TOKEN" if os.environ.get("DISCORD_BOT_TOKEN")
                              else "config discordBotToken")])
    else:
        line(None, "Discord bot token -- closeout: archive the thread (OPTIONAL)",
             ["not set: closeout still posts the reply, just leaves the thread open",
              "set $DISCORD_BOT_TOKEN or config 'discordBotToken'",
              "needs a bot in the guild with Manage Threads on both forums"])

    # 4 -- Tickets password. Resolves from wrangler.jsonc when the repo is near.
    try:
        pw = lib.tickets_password(cfg)
    except Exception as e:
        pw = None
    if pw:
        src = "$BUG_TICKETS_PASSWORD" if os.environ.get("BUG_TICKETS_PASSWORD") else (
            "config ticketsPassword" if cfg.get("ticketsPassword")
            else "internal-dashboards/wrangler.jsonc")
        line(True, "Dashboard tickets password -- closeout: ticket message + close",
             ["source: %s" % src, "dashboard: %s" % lib.dashboard_url(cfg)])
    else:
        line(None, "Dashboard tickets password -- closeout: ticket message + close",
             ["not resolved: closeout skips steps 1+2 (Discord steps still run)",
              "set $BUG_TICKETS_PASSWORD, or config 'ticketsPassword', or point",
              "config 'dmhubRepo' at the dmhub checkout so TICKETS_PASSWORD can be",
              "read from internal-dashboards/wrangler.jsonc"])

    # 5 -- Worker ADMIN_SECRET. Only send-game-chat into a DO-backed game.
    rel = os.environ.get("DMHUB_ADMIN_SECRET") or _first_file(
        cdir, ("admin-secret.txt", "MCDM_CLOUDFLARE_SECRET.txt"))
    stg = os.environ.get("DMHUB_ADMIN_SECRET_STAGING") or _first_file(
        cdir, ("admin-secret-staging.txt",))
    detail = ["release: %s" % (rel or "not set"), "staging: %s" % (stg or "not set")]
    if rel or stg:
        line(True, "Worker ADMIN_SECRET -- send-game-chat into a DO game", detail)
    else:
        line(None, "Worker ADMIN_SECRET -- send-game-chat into a DO game (OPTIONAL)",
             detail + [
                 "only needed to post a Codex Team chat line into a DurableObjects game",
                 "set $DMHUB_ADMIN_SECRET, or save the value in %s"
                 % os.path.join(cdir, "admin-secret.txt"),
                 "the value is whatever `wrangler secret put ADMIN_SECRET` last set"])

    print("")
    if ok:
        print("Core credentials OK: reports can be loaded and fixes worked on.")
        print("Anything marked [--] above only limits the closeout / notify steps.")
    else:
        print("NOT usable yet: fix the [MISSING] items above.")
    return 0 if ok else 1


def _first_file(d, names):
    for n in names:
        p = os.path.join(d, n)
        if os.path.isfile(p):
            return p
    return None


if __name__ == "__main__":
    sys.exit(main())
