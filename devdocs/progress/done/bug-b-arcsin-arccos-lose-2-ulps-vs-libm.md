---
track: B
prio: 20
type: bug
summary: "ArcSin/ArcCos in lib/rtl/math.pas are 1-2 ulps off libm for mid-range arguments (asin(0.5) answers ...982991 where libm and CPython say ...982989); ArcTan agrees exactly"
status: done
owner: track-b-bughunt
---

# `ArcSin` / `ArcCos` lose up to 2 ulps

- **Type:** bug (accuracy) — **Track B** (`lib/rtl/math.pas`)
- **Found:** 2026-08-15, wiring `math.asin`/`acos`/`atan` for NilPy
  ([[bug-nilpy-math-surface-remaining-gaps-and-degrees-association]]). The
  NAMES now resolve; this is what the values then showed.

```
             pxx                  CPython / libm
asin(0.5)    0.5235987755982991   0.5235987755982989
acos(0.5)    1.0471975511965974   1.0471975511965979
atan(2.0)    1.1071487177940904   1.1071487177940904   <- exact
asin(0)      0.0                  0.0                  <- exact
acos(1)      0.0                  0.0                  <- exact
```

So the endpoints and the whole of `ArcTan` are right, and the error appears
for mid-range arguments — which points at the identity used to build asin/acos
on top of arctan (`asin(x) = atan(x / sqrt(1 - x²))` and its acos sibling)
rather than at `ArcTan` itself. That form loses bits twice: in `1 - x²` for x
near ±1, and in the division.

Low priority by the standing rule that float-accuracy work is mechanical and
cheap to defer — filed so the measurement is not lost, not because anything is
blocked on it. `lib/rtl/math.pas` already carries a correctly-rounded `Sqrt`
(with a Dekker two-product correction), so the file's own bar is higher than
this.

## Gate

`test/lib_math_correctly_rounded.pas` extended with asin/acos across
[-1, 1] against a reference table, and the NilPy row re-diffed:
`math.asin(0.5)` / `math.acos(0.5)` matching CPython exactly. The NilPy test
`test/test_nilpy_math_surface_and_random.npy` deliberately asserts only the
exact cases today; add the mid-range ones when this lands.

## Resolution (2026-08-15) — ported onto the double-double kernel

Fixed by moving ArcTan, ArcSin and ArcCos onto the same double-double kernel
`Ln`/`Exp` already run on, mirroring `lib/crtl/src/math.c` — the second time
this file has deleted a plain-double mechanism rather than patched one
(`feature-rtl-ln-exp-are-a-ulp-off-port-the-crtl-dd-core` was the first).

### The ticket UNDERSTATED it, and one of its claims was wrong

Measured before the change, against glibc over ~3000 random arguments each:

| | mismatches | worst |
| --- | --- | --- |
| ArcSin | 1977 / 3009 | 8 ulp |
| ArcCos | 1263 / 3009 | **1099 ulp** |
| ArcTan | 2065 / 3005 | 4 ulp |

So this was not "1-2 ulps for mid-range arguments" — it was most arguments.
And **"ArcTan agrees exactly" was a sample of one**: `atan(2.0)` happens to be
right, and 69% of random arguments were not. A single agreeing value is not
evidence of agreement; that is the whole lesson of this ticket.

The 1099 ulp is the interesting one and it was structural: `ArcCos` was
`pi/2 - ArcSin(x)`, and for x near 1 the answer is near zero, so the
subtraction cancels catastrophically. ArcCos now computes
`atan(sqrt(1-x^2)/x)` directly, so a small result is computed small instead of
as the difference of two large ones.

### After

`ArcTan` 0/3005. `ArcSin` and `ArcCos` differ from glibc on 7 of 3009 — and
**80-digit arithmetic says we are right on all 7 and glibc is wrong**. This is
the `Log10` situation in the same file: glibc's asin/acos are not
correctly-rounded routines. The reference was validated the only way that
means anything before being believed — it agrees with glibc on 200/200 fresh
values, then sides with us on the disputed ones. Arbitrated over the full
sample:

```
asin: pxx 0/3000 wrong,  glibc 6/3000 wrong
acos: pxx 0/3000 wrong,  glibc 1/3000 wrong
```

Also verified under qemu on i386, aarch64 and arm32 — the kernel is plain
Pascal, and none of this is x86-specific.

### Kept, and why

The identity is unchanged: `asin(x) = atan(x/sqrt(1-x^2))`. Only the arithmetic
changed. Two details carry most of it, both commented in the source: `1-x^2` is
formed as the exact product `(1-x)(1+x)` for |x| > 0.5 (Sterbenz — no
cancellation), and acos does not go through asin.

Tests: `test/lib_math_correctly_rounded.pas` gains 7 arbitrated rows marked
DO NOT "fix" to match CPython, plus agreeing rows and the endpoint cases; and
`test/test_nilpy_math_surface_and_random.npy` gains the mid-range row the
ticket asked for (`math.asin(0.5)`, `math.acos(0.5)`, `math.atan(2.0)`,
`math.acos(0.9999)`), which now match CPython exactly.

## Log
- 2026-08-15 — resolved, commit 1a35da630.
