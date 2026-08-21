"""Report which bug-fix credentials are configured, and how to supply the rest.

Run this before anything else when a bug-fix step fails with a credentials
error, or when setting the skill up on a new machine:

    python check-credentials.py

It never prints a secret -- only whether one resolved, and from where. Exit
code 0 if the core credential (the dashboard password) works, 1 if not;
optional credentials that are missing are reported as such but do not fail the
run.

There is deliberately NO Firebase service-account key here. The bug system is
reached through /api/bugs/* on the internal-dashboards Worker, which holds that
key server-side and exposes only the bug system. The credentials, and what each
unlocks:

  1. Dashboard team password          REQUIRED -- reports, tickets, in-game chat
  2. Discord webhook(s)               closeout step 3 (the reply)
  3. Discord bot token                closeout step 4 (archiving the thread)
  4. Worker ADMIN_SECRET              send-game-chat into a DurableObjects game

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

    cfg = lib.load_config()
    cfg_path = cfg.get("_configPath")
    print("config:   %s" % (cfg_path or "(none -- optional; only the Discord steps need it)"))
    if cfg.get("_credentialsDir"):
        print("creds dir: %s" % cfg["_credentialsDir"])
    print("dashboard: %s" % lib.dashboard_url(cfg))
    print("")

    ok = True

    # 1 -- The dashboard password. Everything except Discord runs through it.
    pw = None
    try:
        pw = lib.tickets_password(cfg)
    except Exception:
        pass
    if not pw:
        ok = False
        line(False, "Dashboard team password (REQUIRED)",
             ["not resolved from any source",
              "set $BUG_TICKETS_PASSWORD, or config 'ticketsPassword', or point",
              "config 'dmhubRepo' at the dmhub checkout so TICKETS_PASSWORD can be",
              "read out of internal-dashboards/wrangler.jsonc (running from inside",
              "that repo finds it with no configuration at all)"])
    else:
        src = ("$BUG_TICKETS_PASSWORD" if os.environ.get("BUG_TICKETS_PASSWORD")
               else "config ticketsPassword" if cfg.get("ticketsPassword")
               else "internal-dashboards/wrangler.jsonc")
        # Prove it end to end: log in and read the bug system.
        try:
            st = lib.bugs().status()
            line(True, "Dashboard team password (REQUIRED)",
                 ["source: %s" % src,
                  "logged in as %r; /BugReports holds %d un-triaged report(s)"
                  % (st.get("name"), st.get("untriagedReports", 0))])
        except SystemExit as e:
            ok = False
            line(False, "Dashboard team password (REQUIRED)",
                 ["source: %s" % src, str(e).splitlines()[0]])
        except Exception as e:
            ok = False
            line(False, "Dashboard team password (REQUIRED)",
                 ["source: %s" % src,
                  "resolved, but the bug API rejected it: %s" % e,
                  "if that is a 404, the Worker predates /api/bugs/* -- deploy",
                  "internal-dashboards (npm run deploy)"])

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
        line(None, "Discord webhook(s) -- closeout: reply to the thread (OPTIONAL)",
             ["not set: closeout can still do the ticket half, not the Discord half",
              "set 'discordWebhook' (and optionally 'channels') in %s"
              % (cfg_path or "bug-report-config.json"),
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

    # 4 -- Worker ADMIN_SECRET. Only send-game-chat into a DO-backed game; a
    #      Firebase-backed game is written by the dashboard and needs nothing.
    cdir = cfg.get("_credentialsDir")
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
                 "only needed for a DurableObjects game; the dashboard writes a",
                 "Firebase-backed game itself",
                 "set $DMHUB_ADMIN_SECRET, or save the value in %s"
                 % os.path.join(cdir or "<credentials dir>", "admin-secret.txt"),
                 "the value is whatever `wrangler secret put ADMIN_SECRET` last set"])

    print("")
    if ok:
        print("Core credential OK: reports can be loaded and fixes worked on.")
        print("Anything marked [--] above only limits the closeout / notify steps.")
        print("No Firebase key is needed, or wanted, on this machine.")
    else:
        print("NOT usable yet: fix the [MISSING] items above.")
    return 0 if ok else 1


def _first_file(d, names):
    if not d:
        return None
    for n in names:
        p = os.path.join(d, n)
        if os.path.isfile(p):
            return p
    return None


if __name__ == "__main__":
    sys.exit(main())
