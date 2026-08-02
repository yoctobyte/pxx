---
track: B
prio: 35
type: feature
---

# `localtime()` returns UTC, so every local timestamp a C program prints is wrong

- **Type:** feature (crtl) — **Track B** (`lib/crtl/src/time.c`)
- **Filed:** 2026-08-02 from the round-3/4 behavioural probe of
  [[feature-crtl-implement-libc-assumptions]].

## This is a documented limitation, not an undiscovered bug

`lib/crtl/src/time.c:96` says so plainly:

```c
/* No timezone database — local time == UTC. */
struct tm *localtime(const time_t *timer) { return gmtime(timer); }
```

What had not been done is measuring what that costs a program, which is the
reason to file rather than leave it as a comment.

## Measured against gcc, same fixed instant (`t = 1700000000`)

| `TZ` | gcc local hour | pxx local hour |
| --- | --- | --- |
| `UTC` | 22:13 | 22:13 |
| `Europe/Amsterdam` | **23:13** (+1) | 22:13 |
| `America/New_York` | **17:13** (−5) | 22:13 |

`gmtime`, `mktime`, `strftime`, `difftime`, leap days and year boundaries are
all **identical to gcc** — verified under `TZ=UTC` across the whole surface. The
divergence is exactly and only the timezone offset.

## Why it matters

Nothing errors and nothing warns, so a program that logs, names files by
timestamp, or shows a user a time silently shows UTC. Already observed in the
wild in this tree: pdfgen's `/CreationDate` came out at 08:27 where a gcc-built
pdfgen wrote 10:27 on the same box — noticed only because the two were being
diffed for an unrelated reason.

It is also the kind of wrong that survives review: 22:13 is a perfectly
plausible time.

## Fix shape — TZif, not a half-measure

The correct source is `/etc/localtime`, a TZif binary: header, transition
times, per-transition type indices, and `ttinfo` records carrying
`gmtoff`/`isdst`/abbreviation. "Offset in effect at time T" is a binary search
over the transition table — bounded work, no tzdata text parsing, and it gets
DST right by construction because the transitions are precomputed in the file.

**Do not implement the `TZ`-string form alone** (`CET-1CEST,M3.5.0,M10.5.0/3`).
Parsing just the leading offset and skipping the DST rule gives an answer that
is right for half the year and wrong for the other half, with nothing to
indicate which — strictly worse than today's honest, uniform UTC, and precisely
the silent-half-right outcome this project rejects elsewhere. If the `TZ`
string is supported it must include the rule.

`tzset`/`tzname`/`timezone`/`daylight` come along with this, and `mktime` needs
the inverse mapping to stay consistent with whatever `localtime` reports.

## Gate

The table above reproduced against gcc for several zones including a
southern-hemisphere one (DST inverted) and one with a non-whole-hour offset
(`Asia/Kolkata`, +5:30), plus an instant either side of a DST transition in both
directions. `TZ=UTC` output must be byte-unchanged — that is what the existing
`test/` time coverage pins today. Cross-target, since `lib/crtl` builds for
every target.
