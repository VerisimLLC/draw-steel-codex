"""Close out a feedback report once its fix has landed.

Three outward-facing steps, in order (each can be skipped; --dry-run previews all):

  1. Post a developer message onto the reporter's ticket, through the team
     dashboard's tickets API (so it carries the dashboard's dev name, bumps
     lastDevMessageAt and fires the in-app "developer responded" marker).
  2. Set that ticket's status to closed.
  3. Reply "Fixed and Closed" into the issue's Discord thread (in #bugs or
     #user-feedback, whichever the thread was opened in).
  4. Archive that thread, so it drops off the forum's active list.

Steps 3+4 run only when the issue HAS a thread. Since 2026-09-17 triage no longer
opens one per issue -- the thread is the issue node's `threadId` field, present
only once a human opened one -- so an issue with none skips them with a note.

Usage:
  python bug-close-out.py <reportId> [options]

Options:
  --dry-run              print what would be sent; write nothing, post nothing
  --message TEXT         override the ticket message (default: the thank-you line)
  --discord-text TEXT    override the Discord reply (default: "Fixed and Closed")
  --dev-name NAME        dashboard display name to post as (default: Codex Developers)
  --thread KEY           issue to reply into instead of the report's triage.issueId.
                         An issue registry KEY: the dashboard resolves the thread
                         from the issue node, so a raw Discord thread id only works
                         for issues from before 2026-09-17 (key == thread id)
  --no-ticket            skip steps 1+2 (Discord only)
  --no-discord           skip steps 3+4 (ticket only)
  --no-archive           post the reply but leave the thread open

Config / secrets, in resolution order:
  dashboard url       bug-report-config.json "dashboardUrl"     -> DASHBOARD_URL_DEFAULT
  tickets password    $BUG_TICKETS_PASSWORD -> config "ticketsPassword"
                      -> TICKETS_PASSWORD in internal-dashboards/wrangler.jsonc,
                      looked for at $INTERNAL_DASHBOARDS_WRANGLER, then under
                      config "dmhubRepo", then in any ancestor of the cwd, then
                      in a dmhub repo sibling to this script
  discord webhook     bug-report-config.json "channels"/"discordWebhook", picked
                      by the thread's channelKey (see bugreport_lib)
  discord bot token   $DISCORD_BOT_TOKEN -> config "discordBotToken". Step 4 only;
                      webhooks cannot archive threads. Absent => step 4 is skipped
                      with a note, which is not a failure.

Not every report has a ticket: tickets are only opened for bug-type reports filed
by ticket-aware clients. A missing ticket is reported and skipped, not an error --
the Discord step still runs. Prints a per-step summary; exits non-zero if a step
that was meant to run failed.

The same three steps run automatically, without a human, when a fix PR raised by
triage is merged -- see bug-report-check-prs.py. Use this script for the manual
case: a fix that shipped some other way, or a report you want to close by hand.
"""

import sys

import bugreport_lib as lib

# Windows consoles default to cp1252, but report text is arbitrary user content
# (emoji, narrow no-break spaces, em dashes). Without this, a write dies mid-stream
# with UnicodeEncodeError and truncates the output -- silently, when redirected.
for _stream in (sys.stdout, sys.stderr):
    try:
        _stream.reconfigure(encoding="utf-8")
    except (AttributeError, ValueError):
        pass


MESSAGE_DEFAULT = (
    "Thank you for reporting this issue, we have a fix scheduled with the next update"
)
DISCORD_TEXT_DEFAULT = "Fixed and Closed"


# ---------------------------------------------------------------- main

def parse_args(argv):
    # argv[0] is the report id; push ids start with '-', which argparse would
    # treat as a flag, so parse by hand (same reason as bug-report-get.py).
    if not argv or argv[0] in ("-h", "--help"):
        print(__doc__)
        sys.exit(0 if argv else 2)
    opts = {
        "rid": argv[0],
        "dry_run": False,
        "message": MESSAGE_DEFAULT,
        "discord_text": DISCORD_TEXT_DEFAULT,
        "dev_name": lib.DEV_NAME_DEFAULT,
        "thread": None,
        "ticket": True,
        "discord": True,
        "archive": True,
    }
    i = 1
    takes_value = {
        "--message": "message",
        "--discord-text": "discord_text",
        "--dev-name": "dev_name",
        "--thread": "thread",
    }
    while i < len(argv):
        a = argv[i]
        if a == "--dry-run":
            opts["dry_run"] = True
        elif a == "--no-ticket":
            opts["ticket"] = False
        elif a == "--no-discord":
            opts["discord"] = False
        elif a == "--no-archive":
            opts["archive"] = False
        elif a in takes_value:
            i += 1
            if i >= len(argv):
                raise SystemExit("%s needs a value" % a)
            opts[takes_value[a]] = argv[i]
        else:
            raise SystemExit("Unknown option: %s" % a)
        i += 1
    return opts


def main():
    o = parse_args(sys.argv[1:])
    cfg = lib.load_config()
    rid = o["rid"]
    tag = "[dry-run] " if o["dry_run"] else ""

    data = lib.bugs().report(rid)
    source, report = data.get("source"), data.get("report")
    if report is None:
        raise SystemExit("Report %s not found in /BugReports or /BugReportsArchive." % rid)
    uid = report.get("userid")
    issue = data.get("issue")
    # The Discord calls take the issue KEY and the dashboard resolves its thread.
    # The key is not itself a thread id (see lib.issue_thread), so look the thread
    # up here only to know whether there is one to reply into.
    issue_id = o["thread"] or (report.get("triage") or {}).get("issueId")
    thread_id = None
    if o["thread"]:
        # Override: we have no node for it, so let the dashboard resolve it.
        thread_id = o["thread"]
        no_thread = None
    elif not issue_id:
        no_thread = "report not triaged, so no issue or thread (pass --thread)"
    elif not issue:
        no_thread = "issue %s not found in the registry" % issue_id
    else:
        thread_id = lib.issue_thread(issue)
        no_thread = None if thread_id else "issue %s has no Discord thread" % issue_id
    # Which forum the thread lives in. Informational: the dashboard picks the
    # webhook from the issue node itself and ignores this.
    channel_key = (issue or {}).get("channelKey")

    print("Report %s (%s)" % (rid, source))
    print("  user    : %s" % (uid or "(none)"))
    print("  issue   : %s" % (issue_id or "(none)"))
    if o["thread"]:
        print("  thread  : resolved by the dashboard from --thread %s" % o["thread"])
    else:
        print("  thread  : %s" % (thread_id or "(none -- %s)" % no_thread))

    steps = []   # (label, ok, detail)

    # 1 + 2: ticket message, then close.
    if not o["ticket"]:
        steps.append(("ticket", None, "skipped (--no-ticket)"))
    elif not uid:
        steps.append(("ticket", False, "report has no userid"))
    elif not lib.ticket_exists(uid, rid):
        # Expected for feature/feedback reports and pre-ticket clients.
        steps.append(("ticket", None, "no ticket at /Tickets/%s/%s -- skipped" % (uid, rid)))
    else:
        print("\n%smessage as %r -> /Tickets/%s/%s:\n  %s"
              % (tag, o["dev_name"], uid, rid, o["message"]))
        print("%sstatus -> closed" % tag)
        if not o["dry_run"]:
            tickets = lib.TicketsClient(cfg, o["dev_name"])
            try:
                tickets.message(uid, rid, o["message"])
                steps.append(("ticket message", True, "posted as %s" % o["dev_name"]))
                tickets.close(uid, rid)
                steps.append(("ticket close", True, "status=closed"))
            except RuntimeError as e:
                # Report it in the summary rather than aborting -- the Discord
                # step is independent and still worth running.
                steps.append(("ticket", False, str(e)))
        else:
            steps.append(("ticket message", None, "would post"))
            steps.append(("ticket close", None, "would close"))

    # 3 + 4: Discord thread reply, then archive the thread. Order matters --
    # posting into an archived thread un-archives it, so the reply goes first.
    if not o["discord"]:
        steps.append(("discord", None, "skipped (--no-discord)"))
    elif not thread_id:
        # Ordinary since threads became optional: nothing to reply into or archive.
        steps.append(("discord", None, "skipped -- %s" % no_thread))
    else:
        print("\n%sdiscord reply -> issue %s, thread %s:\n  %s"
              % (tag, issue_id, thread_id, o["discord_text"]))
        if not o["dry_run"]:
            lib.discord_reply(cfg, issue_id, o["discord_text"], channel_key=channel_key)
            steps.append(("discord", True, "replied to thread %s" % thread_id))
        else:
            steps.append(("discord", None, "would reply"))

        if not o["archive"]:
            steps.append(("archive thread", None, "skipped (--no-archive)"))
        elif not lib.discord_bot_token(cfg):
            steps.append(("archive thread", None,
                          "no bot token configured -- thread left open"))
        elif o["dry_run"]:
            print("%sarchive thread %s" % (tag, thread_id))
            steps.append(("archive thread", None, "would archive"))
        else:
            steps.append(("archive thread",) + lib.discord_archive_thread(cfg, issue_id))

    print("\nSummary%s:" % (" (dry run -- nothing sent)" if o["dry_run"] else ""))
    failed = False
    for label, ok, detail in steps:
        mark = "ok  " if ok else ("FAIL" if ok is False else "--  ")
        failed = failed or ok is False
        print("  %s %-15s %s" % (mark, label, detail))
    sys.exit(1 if failed else 0)


if __name__ == "__main__":
    main()
