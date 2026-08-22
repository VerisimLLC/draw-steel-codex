#!/usr/bin/env python3
"""
report-do.py -- Scan a DMHub game's Durable Object and print a report.

Reads from the Cloudflare Worker's admin API endpoints to surface:
  - Session stats (in-memory counters for the current DO instance)
  - Database state (actual SQLite rows on disk, with breakdown + largest)
  - Flush audit log (recent save attempts, with errors highlighted)
  - Destructive PUT log (any historical root-wipe writes)
  - Errors from the central ErrorCollector filtered to this game

Usage:
    python report-do.py <gameid> --staging
    python report-do.py <gameid> --rel

Flags:
    --staging / --rel   pick environment (one required)
    --errors N          max ErrorCollector rows to show (default 20)
    --audit N           max flush-audit rows to show (default 20)
    --largest N         top N largest SQLite rows to show (default 10)
"""

import argparse
import json
import sys
import urllib.request
import urllib.error
from collections import Counter
from datetime import datetime, timezone

# Windows consoles default to cp1252, but report text is arbitrary user content
# (emoji, narrow no-break spaces, em dashes). Without this, a write dies mid-stream
# with UnicodeEncodeError and truncates the output -- silently, when redirected.
for _stream in (sys.stdout, sys.stderr):
    try:
        _stream.reconfigure(encoding="utf-8")
    except (AttributeError, ValueError):
        pass


STAGING_URL = "https://game-server-staging.purchase-a5b.workers.dev"
RELEASE_URL = "https://game-server.purchase-a5b.workers.dev"

# Cloudflare's bot-protection rejects the default Python-urllib User-Agent
# with a 403/Error 1010. Sending a plain-looking UA gets us through.
USER_AGENT = "dmhub-admin-report-do/1.0"


def fetch_json(url, timeout=30):
    """GET a JSON endpoint. Returns parsed dict, or {'_error': ...} on failure."""
    req = urllib.request.Request(url, headers={
        "Accept": "application/json",
        "User-Agent": USER_AGENT,
    })
    try:
        with urllib.request.urlopen(req, timeout=timeout) as resp:
            return json.loads(resp.read().decode("utf-8"))
    except urllib.error.HTTPError as e:
        body = ""
        try:
            body = e.read().decode("utf-8", errors="replace")[:200]
        except Exception:
            pass
        return {"_error": "HTTP {}: {}".format(e.code, e.reason), "_body": body}
    except urllib.error.URLError as e:
        return {"_error": "URL error: {}".format(e.reason)}
    except Exception as e:
        return {"_error": "{}: {}".format(type(e).__name__, e)}


def format_bytes(n):
    """Human-readable byte count."""
    n = float(n)
    for unit in ("B", "KB", "MB", "GB"):
        if n < 1024:
            return "{:.1f} {}".format(n, unit)
        n /= 1024
    return "{:.1f} TB".format(n)


def format_ts(ms):
    """Unix ms to human-readable UTC string."""
    if not ms:
        return "-"
    try:
        return datetime.fromtimestamp(ms / 1000, tz=timezone.utc).strftime("%Y-%m-%d %H:%M:%S UTC")
    except (ValueError, OSError):
        return str(ms)


def print_header(title):
    bar = "=" * (len(title) + 4)
    print()
    print(bar)
    print("  {}".format(title))
    print(bar)


def print_section(title):
    print()
    print("--- {} ---".format(title))


def classify_shard(name):
    """Group a SQLite row name into a logical bucket for the breakdown."""
    if name.startswith("game::"):
        rest = name[len("game::"):]
        if "/" not in rest:
            return "game::" + rest
        parts = rest.split("/")
        top = parts[0]
        # Deep-sharded asset collections have one more level of grouping.
        if top == "assets" and len(parts) >= 3 and parts[1] in ("monsters", "objectTables", "pdfDocuments"):
            return "game::assets/" + parts[1]
        return "game::" + top
    if "::" in name:
        left = name.split("::", 1)[0]
        if left.startswith("mapdetails:"):
            return "mapdetails:*"
        if left.startswith("maps:"):
            return "maps:*"
        return left + "::*"
    return name


def report_memory(base, gid):
    print_section("MEMORY PRESSURE (in-memory stores)")
    mem = fetch_json("{}/api/{}/memory".format(base, gid))
    if "_error" in mem:
        print("  ERROR: {}".format(mem["_error"]))
        if mem.get("_body"):
            print("  body: {}".format(mem["_body"]))
        return

    total_json = mem.get("totalJsonBytes", 0)
    est_heap = mem.get("estimatedHeapBytes", 0)
    limit = mem.get("limitBytes", 0)
    pct = mem.get("percentOfLimit", 0.0)
    mult = mem.get("multiplier", 3)

    # Severity marker based on % of limit
    if pct >= 85:
        marker = "!!! CRITICAL !!!"
    elif pct >= 70:
        marker = "!! WARNING !!"
    elif pct >= 50:
        marker = "! caution !"
    else:
        marker = "ok"

    print("  total JSON bytes:  {:,} ({})".format(total_json, format_bytes(total_json)))
    print("  estimated heap:    {:,} ({}) -- at {}x multiplier".format(est_heap, format_bytes(est_heap), mult))
    print("  128 MiB limit:     {:,} ({})".format(limit, format_bytes(limit)))
    print("  percent of limit:  {:.1f}%  [{}]".format(pct, marker))
    print("  stores loaded:     {}".format(mem.get("storesCount", 0)))
    print("  note: heap estimate is JSON-size x {}, which is a rough V8".format(mult))
    print("        proxy. Real heap is typically 2x to 4x the JSON size;".format())
    print("        treat this as a ballpark, not a hard measurement.")

    stores = mem.get("stores", [])
    if stores:
        print()
        print("  top stores by size:")
        for s in stores[:10]:
            name = s.get("name", "?")
            bytes_ = s.get("jsonBytes", 0)
            pct_of_total = (bytes_ / total_json * 100.0) if total_json > 0 else 0.0
            print("    {:>10}  ({:>5.1f}%)  {}".format(format_bytes(bytes_), pct_of_total, name))
            # Show top-level keys of the biggest stores
            top_keys = s.get("topKeys", [])[:5]
            for tk in top_keys:
                k = tk.get("key", "?")
                kbytes = tk.get("jsonBytes", 0)
                entries = tk.get("entries")
                entries_str = " ({} entries)".format(entries) if entries is not None else ""
                if kbytes > 1024:  # only show non-trivial keys
                    print("        {:>10}  {}{}".format(format_bytes(kbytes), k, entries_str))


def report_session_stats(base, gid):
    print_section("SESSION STATS (current DO instance, in-memory)")
    stats = fetch_json("{}/api/{}/stats".format(base, gid))
    if "_error" in stats:
        print("  ERROR: {}".format(stats["_error"]))
        if stats.get("_body"):
            print("  body: {}".format(stats["_body"]))
        return

    sd_ms = stats.get("sessionDurationMs", 0)
    start_ms = stats.get("sessionStartTime", 0)
    print("  session started:      {}".format(format_ts(start_ms)))
    print("  session duration:     {:.1f}s ({:.1f} min)".format(sd_ms / 1000.0, sd_ms / 60000.0))
    print("  connected clients:    {}".format(stats.get("connectedClients", 0)))
    stores = stats.get("storesLoaded", [])
    print("  stores loaded:        {}".format(len(stores)))
    print("  row writes (session): {}".format(stats.get("rowWrites", 0)))
    print("  row deletes (session):{}".format(stats.get("rowDeletes", 0)))
    dirty = stats.get("pendingDirtyShards", 0)
    dirty_note = ""
    if dirty > 0:
        dirty_note = "  <-- unflushed writes in memory"
    print("  pending dirty shards: {}{}".format(dirty, dirty_note))
    print("  latest recent-write seq: {}".format(stats.get("latestSeq", 0)))


def report_database_state(base, gid, largest_n):
    print_section("DATABASE STATE (persisted to SQLite)")
    raw = fetch_json("{}/api/{}/raw-rows".format(base, gid))
    if "_error" in raw:
        print("  ERROR: {}".format(raw["_error"]))
        if raw.get("_body"):
            print("  body: {}".format(raw["_body"]))
        return

    rows = raw.get("rows", [])
    total_bytes = sum(r.get("len", 0) for r in rows)
    print("  total rows:  {}".format(raw.get("count", len(rows))))
    print("  total bytes: {:,} ({})".format(total_bytes, format_bytes(total_bytes)))

    if not rows:
        print("  (no rows -- empty game or unreachable)")
        return

    # Breakdown by logical collection
    breakdown = Counter()
    for r in rows:
        breakdown[classify_shard(r["name"])] += 1
    print()
    print("  row breakdown:")
    for key, count in sorted(breakdown.items(), key=lambda x: (-x[1], x[0])):
        print("    {:>6}  {}".format(count, key))

    # Top N largest rows
    if largest_n > 0:
        print()
        print("  top {} largest rows:".format(largest_n))
        largest = sorted(rows, key=lambda r: -r.get("len", 0))[:largest_n]
        for r in largest:
            print("    {:>12}  {}".format(format_bytes(r["len"]), r["name"]))


def report_flush_audit(base, gid, limit):
    print_section("FLUSH AUDIT (last {})".format(limit))
    fa = fetch_json("{}/api/{}/flush-audit?limit={}".format(base, gid, limit))
    if "_error" in fa:
        print("  ERROR: {}".format(fa["_error"]))
        if fa.get("_body"):
            print("  body: {}".format(fa["_body"]))
        return

    rows = fa.get("rows", [])
    total_in_ring = fa.get("nextSeq", 0)
    errors = [r for r in rows if r.get("errorMessage")]
    successes = [r for r in rows if not r.get("errorMessage")]
    print("  ring nextSeq: {}, showing {}".format(total_in_ring, len(rows)))
    print("  successes: {}, errors: {}".format(len(successes), len(errors)))

    if not rows:
        print("  (no flush activity recorded for this DO)")
        return

    print()
    for r in rows:  # newest first
        err = r.get("errorMessage")
        tag = "ERR " if err else "    "
        store = (r.get("store") or "")[:28]
        line = "  {}[{:>5}] {} {:12} store={:28} dirty={:>4} W={:>4} D={:>3} F={:>3} {:>8} {:>5}ms".format(
            tag,
            r.get("seq", 0),
            format_ts(r.get("ts", 0)),
            r.get("trigger", "?"),
            store,
            r.get("dirtyAtEntry", 0),
            r.get("shardsWritten", 0),
            r.get("shardsDeleted", 0),
            r.get("shardsFiltered", 0),
            format_bytes(r.get("bytesWritten", 0)),
            r.get("durationMs", 0),
        )
        print(line)
        if err:
            print("        ERROR: {}".format(err[:300]))


def report_destructive_puts(base, gid):
    print_section("DESTRUCTIVE PUT LOG (historical root-wipes)")
    dp = fetch_json("{}/api/{}/destructive-puts".format(base, gid))
    if "_error" in dp:
        print("  ERROR: {}".format(dp["_error"]))
        if dp.get("_body"):
            print("  body: {}".format(dp["_body"]))
        return
    log = dp.get("log", [])
    if not log:
        print("  (none)")
        return
    for rec in log:
        print("  {} userId={}".format(format_ts(rec.get("ts", 0)), rec.get("userId")))
        counts = rec.get("shardCounts") or {}
        if counts:
            print("    wiped collections:")
            for k, v in counts.items():
                print("      {:>6}  {}".format(v, k))
        missing = rec.get("missingShardedKeys") or []
        if missing:
            print("    missing-from-new-data: {}".format(", ".join(missing)))
        new_keys = rec.get("newDataKeys") or []
        if new_keys:
            print("    new-data top-level keys: {}".format(", ".join(sorted(new_keys))))


def report_errors(base, gid, limit):
    print_section("ERROR COLLECTOR (filtered to this game, last {})".format(limit))
    url = "{}/admin/errors?gameId={}&limit={}".format(base, gid, limit)
    err = fetch_json(url)
    if "_error" in err:
        print("  ERROR: {}".format(err["_error"]))
        if err.get("_body"):
            print("  body: {}".format(err["_body"]))
        return

    rows = err.get("rows", [])
    if not rows:
        print("  (no errors recorded for this game)")
        return

    # Grouped summary by (source, errorClass)
    groups = Counter()
    for r in rows:
        key = "{} / {}".format(r.get("source", "?"), r.get("errorClass") or "-")
        groups[key] += 1
    print("  grouped summary:")
    for k, v in groups.most_common():
        print("    {:>4}  {}".format(v, k))

    print()
    print("  individual events (newest first):")
    for r in rows:
        print("  [{:>5}] {} {} class={}".format(
            r.get("seq", 0),
            format_ts(r.get("ts", 0)),
            r.get("source", "?"),
            r.get("errorClass") or "-",
        ))
        if r.get("shardKey"):
            print("        shard: {}".format(r["shardKey"]))
        elif r.get("store"):
            print("        store: {}".format(r["store"]))
        msg = r.get("errorMessage", "")
        if msg:
            print("        msg: {}".format(msg[:250]))
        ctx = r.get("context")
        if ctx:
            ctx_str = json.dumps(ctx) if not isinstance(ctx, str) else ctx
            print("        ctx: {}".format(ctx_str[:300]))


def main():
    parser = argparse.ArgumentParser(
        description="Report on a DMHub Durable Object's state.",
        epilog="Example: python report-do.py LurkingAmazingDecrepitRaider --staging",
    )
    parser.add_argument("gameid", help="Game ID to inspect")
    env_group = parser.add_mutually_exclusive_group(required=True)
    env_group.add_argument("--staging", action="store_true", help="Query the staging worker")
    env_group.add_argument("--rel", "--release", dest="release", action="store_true",
                           help="Query the release worker")
    parser.add_argument("--errors", type=int, default=20,
                        help="Max ErrorCollector rows to show (default 20)")
    parser.add_argument("--audit", type=int, default=20,
                        help="Max flush-audit rows to show (default 20)")
    parser.add_argument("--largest", type=int, default=10,
                        help="Top N largest SQLite rows to show (default 10)")
    args = parser.parse_args()

    base = RELEASE_URL if args.release else STAGING_URL
    env_label = "RELEASE" if args.release else "STAGING"

    print_header("DMHub DO Report :: {} :: {}".format(args.gameid, env_label))
    print("  base: {}".format(base))
    print("  run:  {}".format(datetime.now(tz=timezone.utc).strftime("%Y-%m-%d %H:%M:%S UTC")))

    report_session_stats(base, args.gameid)
    report_memory(base, args.gameid)
    report_database_state(base, args.gameid, args.largest)
    report_flush_audit(base, args.gameid, args.audit)
    report_destructive_puts(base, args.gameid)
    report_errors(base, args.gameid, args.errors)

    print()


if __name__ == "__main__":
    try:
        main()
    except KeyboardInterrupt:
        print("\ninterrupted", file=sys.stderr)
        sys.exit(130)
