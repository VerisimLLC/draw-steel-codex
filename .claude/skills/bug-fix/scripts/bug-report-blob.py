"""Download (and gunzip) a bug-report blob by its URL.

Blob ids in a report are full download URLs (e.g. https://codexback.com/<md5>).
log / prevLog blobs are gzip-compressed Unity player logs; screenshots and
attachments are raw. Content-addressed, unauthenticated GET.

Usage:
  python bug-report-blob.py <url>                 # gunzip if gzip, print text to stdout
  python bug-report-blob.py <url> --out FILE      # write bytes/text to FILE
  python bug-report-blob.py <url> --raw           # never gunzip
  python bug-report-blob.py <url> --tail 400      # only last N lines (logs)

For crash triage the interesting evidence is usually near the end of the log
(and, for crash-then-restart reports, in prevLog rather than log).
"""

import argparse
import gzip
import sys

import requests

# Windows consoles default to cp1252, but report text is arbitrary user content
# (emoji, narrow no-break spaces, em dashes). Without this, a write dies mid-stream
# with UnicodeEncodeError and truncates the output -- silently, when redirected.
for _stream in (sys.stdout, sys.stderr):
    try:
        _stream.reconfigure(encoding="utf-8")
    except (AttributeError, ValueError):
        pass



def main():
    ap = argparse.ArgumentParser(description=__doc__)
    ap.add_argument("url")
    ap.add_argument("--out", help="Write to this file instead of stdout.")
    ap.add_argument("--raw", action="store_true", help="Do not attempt to gunzip.")
    ap.add_argument("--tail", type=int, default=0, help="Only emit the last N lines (text mode).")
    args = ap.parse_args()

    resp = requests.get(args.url, timeout=60)
    resp.raise_for_status()
    data = resp.content

    if not args.raw:
        # gzip magic bytes 1f 8b -- gunzip transparently whether or not the
        # server set a content-encoding header.
        if len(data) >= 2 and data[0] == 0x1F and data[1] == 0x8B:
            try:
                data = gzip.decompress(data)
            except OSError:
                pass  # not actually gzip; fall through with raw bytes

    if args.out:
        with open(args.out, "wb") as f:
            f.write(data)
        sys.stderr.write("wrote %d bytes to %s\n" % (len(data), args.out))
        return

    text = data.decode("utf-8", errors="replace")
    if args.tail > 0:
        text = "\n".join(text.splitlines()[-args.tail:])
    sys.stdout.write(text)
    if not text.endswith("\n"):
        sys.stdout.write("\n")


if __name__ == "__main__":
    main()
