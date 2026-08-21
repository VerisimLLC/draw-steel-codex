"""Fetch a single feedback report by id, from wherever it lives.

Checks /BugReports first (novel/unprocessed), then /BugReportsArchive (processed).
If the report has been triaged, also pulls its issue-registry node so the caller
gets the agent's analysis + Discord thread in one shot.

Usage:
  python bug-report-get.py <reportId>

Prints JSON:
  {
    "found":  true|false,
    "source": "BugReports" | "BugReportsArchive" | null,
    "report": { ...record, "_id": ..., "triage": { issueId, analysis, ... } } | null,
    "issue":  { title, type, signature, status, reportIds, "_threadId": ... } | null
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

    source = None
    report = None
    r = lib.ref("/BugReports/%s" % rid).get()
    if isinstance(r, dict):
        source, report = "BugReports", r
    else:
        r = lib.ref("/BugReportsArchive/%s" % rid).get()
        if isinstance(r, dict):
            source, report = "BugReportsArchive", r

    issue = None
    if report is not None:
        report = dict(report)
        report["_id"] = rid
        issue_id = (report.get("triage") or {}).get("issueId")
        if issue_id:
            node = lib.ref("/BugReportTriage/issues/%s" % issue_id).get()
            if isinstance(node, dict):
                node = dict(node)
                node["_threadId"] = issue_id
                issue = node

    out = {"found": report is not None, "source": source, "report": report, "issue": issue}
    json.dump(out, sys.stdout, indent=2, ensure_ascii=False)
    sys.stdout.write("\n")


if __name__ == "__main__":
    main()
