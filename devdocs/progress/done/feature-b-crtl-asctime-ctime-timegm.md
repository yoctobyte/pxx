---
summary: "crtl had no asctime/asctime_r/ctime/ctime_r/timegm — ctime(&t) is the one-liner everyone reaches for and it was a 'call to undeclared function'"
type: feature
track: B
prio: 40
---

# crtl: `asctime` / `ctime` / `timegm`

- **Type:** feature (gap) — Track B (`lib/crtl/src/time.c`, `include/time.h`)
- **Status:** done
- **Opened / closed:** 2026-08-05
- **Found by:** `tools/gcc_diff_probe.sh`, third case batch
  ([[feature-c-gcc-oracle-differential-probe]]).

Five functions were missing outright — `asctime`, `asctime_r`, `ctime`,
`ctime_r`, `timegm`. `ctime(&t)` is the shortest way to print a time in C, so
this is a gap real code hits immediately; it failed at compile time
("call to undeclared function"), which is the *good* failure mode, but it
failed.

## Implementation notes

- **`asctime`'s layout is fixed by the standard** (C99 7.23.3.1):
  `"Www Mmm dd hh:mm:ss yyyy\n"`, 26 bytes with the NUL, `mday`
  **space**-padded and the time fields zero-padded. Written out literally
  rather than through `strftime`, which has no "%e inside a fixed layout" form
  that would give the space padding. Verified byte-identical to gcc for
  `t = 1000000000`: `Sun Sep  9 01:46:40 2001` — note the two spaces before the
  9, which is exactly the part a `%d`-based version gets wrong.
- **`timegm`** is `mktime` — crtl's `mktime` is already UTC (there is no
  local-time offset in the PAL, and its own comment says "best-effort, UTC").
  It exists under its own name because code that *means* UTC should not have to
  depend on `mktime` happening to be; if a real local-time offset ever lands,
  `timegm` is the one that must not follow it.
- `asctime`/`ctime` use one static buffer, as specified; the `_r` forms take the
  caller's.

## Gate

`gcc_diff_probe` cases `ctime-asctime-shape` and `timegm-roundtrip` byte-match
gcc; clean on native/i386/arm32/aarch64. `gate.sh lib` green, c-testsuite
219/0/1.
