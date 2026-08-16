---
track: N
prio: 40
type: bug
blocked-by: []
summary: "test_nilpy_pow_matches_cpython.expected still asserts `ValueError` for `(-4) ** 0.5`, recorded before `feat(N): Python's complex type` (ba5a9d987) landed — so the RED is a stale expectation, not a regression, and T's bisect will name the feature commit. Re-recording alone does NOT fix it: pxx answers `(-0+2.8284271247461894j)` where CPython gives `(1.7319121124709868e-16+2.8284271247461903j)`, so the real part and ~1 ulp of the imaginary part still differ."
---

# The pow expectation predates the complex type, and pxx's complex pow differs from CPython

Filed 2026-08-16 by the Track A+P session, from the monitor stream, while Track
T was still bisecting this (32 -> 16 commits). **Not fixing it — this is Track
N's file set.** Filed now because the bisect is going to land on a FEATURE
commit and read as a regression, and because the obvious one-line fix is not
enough.

## Measured three ways, on the PINNED binary

Source: `test/test_nilpy_pow_matches_cpython.npy`. One line of output differs;
everything else matches.

| | value for the `(-4) ** 0.5` line |
| --- | --- |
| `test_nilpy_pow_matches_cpython.expected` | `ValueError` |
| **CPython 3 (the actual oracle)** | `(1.7319121124709868e-16+2.8284271247461903j)` |
| **pxx** | `(-0+2.8284271247461894j)` |

So the recorded expectation does not match CPython either — it asserts a
refusal for something CPython computes. It was last written by `6a4fa40ae`
("`**` goes through the RTL's Power"); `ba5a9d987` ("feat(N): Python's complex
type") landed afterwards and changed the answer from a refusal to a complex
number, which is CPython's behaviour and an improvement. Nothing regressed.

This is the shape already on record as *implementing a feature breaks the test
that asserted its absence* — here not a `*_fail.npy` refusal test but a recorded
`.expected` holding the pre-feature refusal, which no `gate.sh quick` can see.

## Two things to fix, and the second is the real one

1. **The stale expectation.** Re-record from CPython, not from pxx — the file's
   whole point is that CPython is the oracle, and it currently is not.
2. **pxx's complex pow does not equal CPython's.** Re-recording alone leaves the
   test red:
   - **real part**: pxx `-0` vs CPython `1.7319121124709868e-16`. Not noise —
     it is structural. CPython evaluates via polar form,
     `r**0.5 * (cos(θ/2) + i·sin(θ/2))` with `θ = π`, and `cos(π/2)` in double
     is `6.123233995736766e-17`, not zero. pxx appears to special-case the
     axis and produce an exact `-0`. Mathematically pxx's is the nicer answer;
     the test is named *matches_cpython*, so matching is the requirement.
   - **imaginary part**: `...461894` vs `...461903`, about 1 ulp — the ordinary
     accuracy tail, and by the standing rule that class is low-priority
     mechanical work.

   The real-part difference is the one to decide deliberately: matching CPython
   means adopting its polar algorithm including the tiny non-zero real part.
   If that is not wanted, then this test cannot assert equality on this line and
   should say so explicitly rather than carrying a value nobody intends to match.

## Why it is filed rather than fixed here

`test-nilpy` and pylib are Track N's file-ownership; this session holds A+P. The
diagnosis is complete enough that whoever picks it up should not need to redo
any of it.

## Note for Track T

The bisect in flight will name `ba5a9d987` (or whichever commit in that range
introduced the complex result). That is the feature landing, not a fault — same
class of misleading-verdict as
[[bug-t-a-timeout-bisects-to-an-innocent-commit]], though for a different
reason: there the signal was a timeout, here the recorded expectation was wrong
before the bisect started.

## Gate

`make test-nilpy` green with the re-recorded expectation, and the `(-4) ** 0.5`
line asserted against `python3` on the same source rather than against a
remembered value.
