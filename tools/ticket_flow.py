#!/usr/bin/env python3
# SPDX-License-Identifier: MPL-2.0
"""ticket_flow.py — the board's filed-vs-solved history, as committed JSON.

Writes `devdocs/progress/ticket-flow.json` for the website to render. The data
already exists; nothing new has to be recorded to produce it:

  track   the `track:` FIELD, via progress.py's Ticket.track — never the
          filename. That property carries a pile of hard-won special cases
          (bug-t-progress-track-detection-prose-mention and friends), so it is
          imported rather than reimplemented.
  filed   the first commit touching that basename under devdocs/progress/
  closed  the first commit where its path is under done/
  kind    `bug-`/`regression-` prefix vs everything else

**Why this is committed JSON and not computed by the site.** The site's content
checkout is `git clone --depth 1` — it has the ticket *files* but no history at
all, so it cannot see a filed date. Either the clone grows a full history on
every pull, or the numbers are derived here, once, where the history already
lives. The derived form is also the verifiable one: it sits in the public repo
next to the tickets it summarises.

One `git log --reverse --name-only` pass over devdocs/progress yields every
date. Renames across status dirs are handled by matching on BASENAME rather
than path, which is why `--follow` (per-file, slow) is not needed.

Run it after resolving tickets, then commit the JSON:

    tools/ticket_flow.py && git add devdocs/progress/ticket-flow.json
"""

import collections
import datetime as dt
import json
import os
import re
import subprocess
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import progress  # noqa: E402  (needs the path above)

ROOT = progress.ROOT
PROG = ROOT / "devdocs" / "progress"
OUT = PROG / "ticket-flow.json"
SWEEPS = PROG / "sweeps.json"

# Tracks below this many tickets get no panel of their own: a curve drawn from
# four tickets is noise with an axis, and the eye reads it as a trend anyway.
# They stay in the totals — the JSON records which ones were folded so the page
# can say so rather than quietly dropping them.
MIN_TICKETS = 40

# Buckets for "how old is what's still open", in days.
AGE_BUCKETS = [(0, 7), (7, 14), (14, 30), (30, None)]

# A day is flagged as a possible undeclared sweep when a track files at least
# this many tickets AND at least this multiple of its own median active day.
# Only a warning — the generator never invents a shaded band, because a band
# asserts intent and only a human knows whether a spike was a campaign.
SPIKE_MIN = 12
SPIKE_FACTOR = 4


def sh(*args):
    return subprocess.run(args, cwd=ROOT, capture_output=True, text=True,
                          check=True).stdout


def week_of(day):
    """Monday of that ISO week, as YYYY-MM-DD — the bucket key."""
    d = dt.date.fromisoformat(day)
    return (d - dt.timedelta(days=d.weekday())).isoformat()


def history():
    """{basename: {'filed': day, 'done': day, 'gone': day}} from one log pass.

    'gone' is the first day the ticket landed in rejected/ or decided/ — off
    the queue, but NOT solved. Keeping the two apart matters: counting a
    rejection as a fix flatters the closed curve, and ignoring it entirely
    leaves a ticket open forever in the running total.
    """
    out = sh("git", "log", "--reverse", "--date=short", "--format=@%cd",
             "--name-only", "--", "devdocs/progress")
    seen = {}
    day = None
    for line in out.splitlines():
        if line.startswith("@"):
            day = line[1:]
            continue
        parts = line.split("/")
        # devdocs/progress/<bucket>/<slug>.md — anything shallower (BOARD.md,
        # README.md) or under tstate/ or fixtures/ is not a ticket.
        if len(parts) != 4 or not line.endswith(".md"):
            continue
        bucket, base = parts[2], parts[3][:-3]
        if bucket in ("tstate", "fixtures", "patches"):
            continue
        rec = seen.setdefault(base, {"filed": day, "done": None, "gone": None})
        if bucket == "done" and rec["done"] is None:
            rec["done"] = day
        if bucket in ("rejected", "decided") and rec["gone"] is None:
            rec["gone"] = day
    return seen


def load_sweeps():
    """Declared bulk-discovery campaigns, to be shaded on the chart.

    Hand-maintained on purpose. A sweep is a statement about INTENT — "we went
    looking, deliberately, in this window" — and no amount of curve-fitting can
    recover intent from a spike. The generator warns about undeclared spikes
    (see check_spikes) but never draws a band it invented.
    """
    if not SWEEPS.is_file():
        return []
    return json.loads(SWEEPS.read_text(encoding="utf-8")).get("sweeps", [])


def check_spikes(per_day, declared):
    """Warn on days that look like a campaign but are not declared as one."""
    covered = []
    for s in declared:
        tracks = s.get("tracks", "*")
        covered.append((dt.date.fromisoformat(s["from"]),
                        dt.date.fromisoformat(s["to"]),
                        "*" if tracks == "*" else set(tracks)))
    warnings = []
    for track, days in per_day.items():
        counts = sorted(days.values())
        if len(counts) < 5:
            continue
        median = counts[len(counts) // 2] or 1
        for day, n in sorted(days.items()):
            d = dt.date.fromisoformat(day)
            if any(a <= d <= b and (ts == "*" or track in ts) for a, b, ts in covered):
                continue
            if n >= SPIKE_MIN and n >= SPIKE_FACTOR * median:
                warnings.append("%s filed %d on %s (median active day %d)"
                                % (track, n, day, median))
    return warnings


def main():
    board = progress.Board()
    hist = history()

    # Anchor on the tickets that exist NOW. A basename in the history that no
    # longer resolves to a ticket was renamed (the board renames slugs freely);
    # counting it would file a ticket that never closes and inflate every open
    # count from that week on.
    tickets = []
    for t in board.tickets:
        h = hist.get(t.slug)
        if not h:
            continue
        # 'A+C' means one ticket owned jointly; it is filed once, so attribute
        # it to the first track rather than double-count it in both panels.
        track = t.track.split("+")[0] or "?"
        tickets.append({
            "slug": t.slug,
            "track": track,
            "bug": t.slug.startswith(("bug-", "regression-")),
            "filed": h["filed"],
            "done": h["done"],
            "gone": h["gone"],
            "status": t.status,
        })

    # Two granularities, deliberately. WEEKS smooth the noise and are what the
    # filed-vs-closed bump is read from. DAYS are what makes a sweep band
    # legible: the CPython campaign ran 2026-07-28..08-02, which is a single
    # weekly bucket — shading it on the weekly axis would cover the whole point
    # of showing it.
    weeks = sorted({week_of(x["filed"]) for x in tickets}
                   | {week_of(x["done"]) for x in tickets if x["done"]})
    windex = {w: i for i, w in enumerate(weeks)}

    first = min(dt.date.fromisoformat(x["filed"]) for x in tickets)
    last = dt.date.today()
    days = [(first + dt.timedelta(days=i)).isoformat()
            for i in range((last - first).days + 1)]
    dindex = {d: i for i, d in enumerate(days)}

    totals = collections.Counter(x["track"] for x in tickets)
    shown = sorted([t for t, c in totals.items() if c >= MIN_TICKETS],
                   key=lambda t: -totals[t])
    folded = sorted([t for t, c in totals.items() if c < MIN_TICKETS],
                    key=lambda t: -totals[t])

    tracks = {}
    for track in shown:
        tracks[track] = {
            "total": totals[track],
            "filed": [0] * len(weeks), "closed": [0] * len(weeks),
            "bug_filed": [0] * len(weeks), "bug_closed": [0] * len(weeks),
            "daily_filed": [0] * len(days), "daily_closed": [0] * len(days),
            "net_open": [0] * len(days),
        }

    per_day = collections.defaultdict(lambda: collections.Counter())
    for x in tickets:
        per_day[x["track"]][x["filed"]] += 1
        d = tracks.get(x["track"])
        if d is None:
            continue
        d["filed"][windex[week_of(x["filed"])]] += 1
        d["daily_filed"][dindex[x["filed"]]] += 1
        if x["bug"]:
            d["bug_filed"][windex[week_of(x["filed"])]] += 1
        if x["done"]:
            d["closed"][windex[week_of(x["done"])]] += 1
            d["daily_closed"][dindex[x["done"]]] += 1
            if x["bug"]:
                d["bug_closed"][windex[week_of(x["done"])]] += 1

    # Running open count, daily. Off-queue = solved OR rejected/decided: a
    # ticket that was answered rather than fixed still stops being work in the
    # queue, and leaving it in would make every lane look permanently swamped.
    for track, d in tracks.items():
        gone = [0] * len(days)
        for x in tickets:
            if x["track"] != track:
                continue
            end = x["done"] or x["gone"]
            if end and end in dindex:
                gone[dindex[end]] += 1
        running = 0
        for i in range(len(days)):
            running += d["daily_filed"][i] - gone[i]
            d["net_open"][i] = running

    today = dt.date.today()
    ages = {t: [0] * len(AGE_BUCKETS) for t in shown}
    open_statuses = {"urgent", "working", "unfinished", "blocked", "backlog",
                     "experimental", "rainy-day"}
    for x in tickets:
        if x["status"] not in open_statuses or x["track"] not in ages:
            continue
        age = (today - dt.date.fromisoformat(x["filed"])).days
        for i, (lo, hi) in enumerate(AGE_BUCKETS):
            if age >= lo and (hi is None or age < hi):
                ages[x["track"]][i] += 1
                break

    sweeps = load_sweeps()
    warnings = check_spikes(per_day, sweeps)

    data = {
        "generated_at": dt.datetime.now(dt.timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ"),
        "head": sh("git", "rev-parse", "--short", "HEAD").strip(),
        "weeks": weeks,
        "days": days,
        "tracks": tracks,
        "folded_tracks": {t: totals[t] for t in folded},
        "min_tickets": MIN_TICKETS,
        "age_buckets": [{"label": ("%d-%d days" % (lo, hi)) if hi else ("%d+ days" % lo),
                         "counts": {t: ages[t][i] for t in shown}}
                        for i, (lo, hi) in enumerate(AGE_BUCKETS)],
        "sweeps": sweeps,
        "ticket_count": len(tickets),
        "undeclared_spikes": warnings,
    }
    OUT.write_text(json.dumps(data, indent=1, sort_keys=True) + "\n", encoding="utf-8")
    print("wrote %s — %d tickets, %d weeks / %d days, %d tracks (%s folded)"
          % (OUT, len(tickets), len(weeks), len(days), len(shown),
             ", ".join(folded) or "none"))
    for w in warnings:
        print("  undeclared spike: %s" % w)
    if warnings:
        print("  ^ if any of those was a deliberate campaign, add it to %s —"
              " an unmarked sweep makes the curve tell a false story." % SWEEPS.name)


if __name__ == "__main__":
    main()
