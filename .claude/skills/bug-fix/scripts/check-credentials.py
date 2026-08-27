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

  1. Dashboard team password          REQUIRED -- the only one a dev holds
  2. Worker ADMIN_SECRET              send-game-chat into a DurableObjects game

The Discord webhooks and bot token are Worker secrets on the dashboard, which
makes the Discord calls itself; this check reports whether they are configured
THERE, which is a property of the deployment rather than of this machine.

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
    print("config:   %s" % (cfg_path or "(none -- optional, and nothing here needs it)"))
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
             ["not found -- see the setup instructions below"])
    else:
        src = lib.password_source(cfg) or "(unknown)"
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

    # 2 + 3 -- Discord. The webhooks and bot token are Worker secrets now; the
    #          dashboard performs the calls, so all we can (and should) learn
    #          from here is whether it is able to.
    dstat = None
    if ok:
        try:
            dstat = (lib.bugs().status().get("discord") or {})
        except Exception:
            dstat = None

    if dstat is None:
        line(None, "Discord -- closeout: reply + archive",
             ["unknown: could not ask the dashboard (see above)"])
    else:
        if dstat.get("webhookError"):
            line(False, "Discord webhook(s) -- closeout: reply to the thread",
                 ["the dashboard's DISCORD_WEBHOOKS is malformed: %s" % dstat["webhookError"],
                  "fix it with: cd internal-dashboards && npx wrangler secret put DISCORD_WEBHOOKS"])
            ok = False
        elif dstat.get("webhooks"):
            line(True, "Discord webhook(s) -- closeout: reply to the thread",
                 ["held by the dashboard; channels: %s" % ", ".join(sorted(dstat["webhooks"]))])
        else:
            line(None, "Discord webhook(s) -- closeout: reply to the thread (OPTIONAL)",
                 ["not configured on the dashboard: closeout can do the ticket half only",
                  "set it with: cd internal-dashboards",
                  "             npx wrangler secret put DISCORD_WEBHOOKS",
                  'value is a JSON map, e.g. {"default":"https://...","bug":"https://..."}'])

        if dstat.get("botToken"):
            line(True, "Discord bot token -- closeout: archive the thread",
                 ["held by the dashboard"])
        else:
            line(None, "Discord bot token -- closeout: archive the thread (OPTIONAL)",
                 ["not configured on the dashboard: closeout still posts the reply,",
                  "it just leaves the thread open",
                  "set it with: cd internal-dashboards",
                  "             npx wrangler secret put DISCORD_BOT_TOKEN",
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
        print("No Firebase key and no Discord secret are needed on this machine --")
        print("the dashboard holds those and acts on your behalf.")
    else:
        print("NOT usable yet: fix the [MISSING] items above.")
        if not pw:
            print("")
            print("-" * 70)
            print(lib.missing_password_message())
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
