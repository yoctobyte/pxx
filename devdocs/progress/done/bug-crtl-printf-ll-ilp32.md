---
prio: 65
---

# crtl printf counted `ll` but never honoured it (arg truncation + shift on ILP32)

- **Type:** bug (correctness)
- **Track:** B — libraries (`lib/crtl/src/stdio.c`)
- **Status:** done — fixed 2026-07-12, commit 3368863b.

## Symptom
printf parsed the length modifiers into `lng` and then did `va_arg(ap, long)` for
every integer conversion. On LP64 that is accidentally correct (`long` == `long
long`). On ILP32 a `long` is 32 bits, so `%llx` consumed only the LOW half of its
argument **and left the high half in the varargs slot**, which the NEXT conversion
then read.

    printf("%llx %d", 0xabcd00000000ULL, 7)   ->   "0 43981"

`43981` is `0xabcd` — the high half of the first argument, printed where the `7`
belonged. So: one wrong value, then every later argument shifted.

## Fix
`__crtl_utoa` and printf's `uv`/`sv` locals are now 64-bit, and each conversion
dispatches on the rank: `lng >= 2` -> `long long`, `lng == 1` -> `long`, else `int`.
The scanf side already did this correctly — printf was the outlier.

## Regression
`test/cprintf_ll_b252.c` (64-bit and 32-bit runs). It checks the ARGUMENT AFTER a
`%ll` too, since the shifted-argument symptom is the one that actually corrupts
output.

## Note
Fixing this is what exposed [[bug-32bit-truthiness-high-half]] — with the full 64
bits finally arriving, `__crtl_utoa`'s `while (v)` mis-branched.
