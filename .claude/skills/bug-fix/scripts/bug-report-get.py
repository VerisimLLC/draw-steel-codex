"""Fetch a single feedback report by id, from wherever it lives.

Checks /BugReports first (novel/unprocessed), then /BugReportsArchive (processed).
If the report has been triaged, also pulls its issue-registry node so the caller
gets the agent's analysis + Discord thread in one shot.

Goes through /api/bugs/report on the internal-dashboards Worker, which holds the
Firebase service account server-side. This machine needs only the shared team
password -- no Firebase credential. See CREDENTIALS.md.

Usage:
  python bug-report-get.py <reportId>

Prints JSON:
  {
    "found":  true|false,
    "source": "BugReports" | "BugReportsArchive" | null,
    "report": { ...record, "_id": ..., "triage": { issueId, analysis, ... } } | null,
    "issue":  { title, type, signature, status, reportIds, "_threadId": ... } | null,
    "ticket": { uid, exists } | null    // is there a user-facing ticket to close
  }
"""

import json
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


def main():
    # NOTE: read argv directly rather than via argparse -- Firebase push ids start
    # with '-' (e.g. -OwzDc6X...), which argparse would treat as an option flag.
    argv = [a for a in sys.argv[1:]]
    if not argv or argv[0] in ("-h", "--help"):
        print(__doc__)
        sys.exit(0 if argv else 2)
    rid = argv[0]

    out = lib.bugs().report(rid)

    json.dump(out, sys.stdout, indent=2, ensure_ascii=False)
    sys.stdout.write("\n")


if __name__ == "__main__":
    main()
