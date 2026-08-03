#!/usr/bin/env python3
# SPDX-License-Identifier: MPL-2.0
"""Is the offload actually working? — numbers for the dev-throughput claim.

The model in meta-t-dev-throughput-and-track-a-t-integration is that dev tracks
stop running suites and Track T owns breadth, which makes **T's report latency
the product**: at a ~15s dev cycle, a late report costs commits to unwind rather
than minutes of waiting. That claim is testable, and this prints the test.

    tools/tstate_stats.py [--host xeon] [--days N]

Reports, per tier:

  commit -> verdict   how long after a commit landed its verdict appeared. This
                      is the number the "Done when" is written in: "hears about
                      any regression it caused within minutes".
  wall                how long a run itself takes — the floor under latency.
  full cadence        gap between successive full-tier runs, and what fraction
                      of tested shas ever get full coverage. Full only backfills
                      while the repo is idle and is preempted by any push, so a
                      busy day can starve it (feature-twatch-full-tier-coverage-age).
  ticket outcomes     what the watcher's auto-filed regression tickets became.
                      A high rejected/fixed ratio means T is spending other
                      agents' triage cycles on noise; a high fixed count is the
                      offload paying for itself.

Reads only committed state (tstate/runs-<host>.ndjson + the board) and git, so
it is safe to run anywhere, any time, and cheap enough to rerun whenever the
claim is in doubt. It measures; it never tunes.
"""
import argparse
import calendar
import json
import os
import subprocess
import sys
import time

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
TSTATE = os.path.join(ROOT, "devdocs", "progress", "tstate")
PROGRESS = os.path.join(ROOT, "devdocs", "progress")


def ts(iso):
    return calendar.timegm(time.strptime(iso, "%Y-%m-%dT%H:%M:%SZ"))


def pct(xs, q):
    xs = sorted(xs)
    return xs[min(len(xs) - 1, int(len(xs) * q))]


def line(label, xs, unit="m", scale=60.0):
    if not xs:
        return "  %-14s (none)" % label
    return ("  %-14s n=%4d   median=%6.1f%s  p90=%6.1f%s  max=%7.1f%s"
            % (label, len(xs), pct(xs, .5) / scale, unit,
               pct(xs, .9) / scale, unit, max(xs) / scale, unit))


def commit_times():
    out = subprocess.run(["git", "log", "--format=%H %ct", "--all"], cwd=ROOT,
                         capture_output=True, text=True).stdout
    return {h: int(c) for h, c in (l.split() for l in out.splitlines() if l)}


def load_runs(host, days):
    path = os.path.join(TSTATE, "runs-%s.ndjson" % host)
    if not os.path.exists(path):
        sys.exit("no run archive for host %r (%s)" % (host, path))
    runs = [json.loads(l) for l in open(path) if l.strip()]
    if days:
        cutoff = time.time() - days * 86400
        runs = [r for r in runs if ts(r["date"]) >= cutoff]
    return sorted(runs, key=lambda r: r["date"])


def ticket_outcomes():
    """What the watcher's own auto-filed tickets became. Bucket IS status."""
    out = {}
    for bucket in ("backlog", "urgent", "working", "unfinished", "blocked",
                   "done", "done-followup", "rejected", "rainy-day"):
        d = os.path.join(PROGRESS, bucket)
        if not os.path.isdir(d):
            continue
        n = sum(1 for f in os.listdir(d) if f.startswith("regression-"))
        if n:
            out[bucket] = n
    return out


def main():
    ap = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    ap.add_argument("--host", default="xeon")
    ap.add_argument("--days", type=float, default=0,
                    help="only runs from the last N days (default: all)")
    args = ap.parse_args()

    runs = load_runs(args.host, args.days)
    if not runs:
        sys.exit("no runs in window")
    ctime = commit_times()

    lat, wall = {}, {}
    first = {}
    for r in runs:
        wall.setdefault(r["tier"], []).append(r["wall"])
        c = ctime.get(r["sha"])
        if c is None:
            continue                  # sha not in this clone (rebased away)
        d = ts(r["date"]) - c
        if d < 0:
            continue                  # clock skew between boxes; not a latency
        lat.setdefault(r["tier"], []).append(d)
        first.setdefault(r["sha"], d)

    print("tstate stats — host %s, %d runs, %s .. %s"
          % (args.host, len(runs), runs[0]["date"], runs[-1]["date"]))

    print("\nCOMMIT -> VERDICT   (the 'hears about it within minutes' claim)")
    for tier in sorted(lat):
        print(line(tier, lat[tier]))
    print(line("ANY (first)", list(first.values())))

    print("\nRUN WALL TIME       (the floor under that latency)")
    for tier in sorted(wall):
        print(line(tier, wall[tier]))

    fulls = [ts(r["date"]) for r in runs if r["tier"] == "full"]
    gaps = [b - a for a, b in zip(fulls, fulls[1:])]
    shas = {r["sha"] for r in runs}
    full_shas = {r["sha"] for r in runs if r["tier"] == "full"}
    print("\nFULL-TIER COVERAGE  (backfills only while idle; any push preempts)")
    print(line("gap", gaps))
    print("  %-14s %d of %d tested shas (%.0f%%)"
          % ("covered", len(full_shas), len(shas),
             100.0 * len(full_shas) / max(1, len(shas))))

    verdicts = {}
    for r in runs:
        verdicts[r["verdict"]] = verdicts.get(r["verdict"], 0) + 1
    n_newred = sum(1 for r in runs if r.get("new_red"))
    print("\nSIGNAL")
    print("  %-14s %s" % ("verdicts", ", ".join("%s=%d" % kv
                                                for kv in sorted(verdicts.items()))))
    print("  %-14s %d of %d runs (%.0f%%)"
          % ("with NEW-RED", n_newred, len(runs), 100.0 * n_newred / len(runs)))
    out = ticket_outcomes()
    if out:
        fixed, rejected = out.get("done", 0), out.get("rejected", 0)
        print("  %-14s %s" % ("auto-tickets",
                              ", ".join("%s=%d" % kv for kv in sorted(out.items()))))
        if fixed + rejected:
            print("  %-14s %.0f%% of resolved auto-tickets were real bugs"
                  % ("precision", 100.0 * fixed / (fixed + rejected)))
    return 0


if __name__ == "__main__":
    sys.exit(main())
