---
track: N
prio: 40
type: bug
blocked-by: []
summary: "test_nilpy_pow_matches_cpython.expected still asserts `ValueError` for `(-4) ** 0.5`, recorded before `feat(N): Python's complex type` (ba5a9d987) landed — so the RED is a stale expectation, not a regression, and T's bisect will name the feature commit. Re-recording alone does NOT fix it: pxx answers `(-0+2.8284271247461894j)` where CPython gives `(1.7319121124709868e-16+2.8284271247461903j)`, so the real part and ~1 ulp of the imaginary part still differ."
status: done
owner: claude-A-P-N
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

## Resolution — the "structural" real-part difference was a plain bug, not a design choice

The filed diagnosis said pxx's exact `-0` real part was structural, that CPython's
`1.73e-16` came from its polar algorithm, and that matching it meant adopting
that algorithm — a call for the owner. **Measuring one level deeper made the
decision disappear: pxx's `-0` was simply wrong.**

`math.cos(math.pi/2)` in NilPy already answers `6.123233995736766e-17`,
correctly, because it name-matches the RTL's `Cos`. But `pycomplex_pow` does not
use that. It calls `PyCxCosSin`, a Taylor series local to pylib, whose argument
reduction was:

```pascal
q := Trunc(t / PyHalfPi + 0.5);
t := t - q * PyHalfPi;          { for x = pi/2 this is EXACTLY 0.0 }
```

`PyHalfPi` is the *double* nearest pi/2, which differs from pi/2 by about
6.12e-17 — and near a quadrant boundary that residual **is** the answer.
Subtracting the constant from itself annihilated it, so `cos(pi/2)` returned
`-0.0`, and every complex result whose real part is nothing but that residual
came out as `-0`. Two implementations of cosine, and complex arithmetic was
reaching the wrong one.

Fixed with a Cody-Waite two-part constant, so the reduction keeps what the
single-double subtraction destroys:

```pascal
PyHalfPiHi = 1.5707963267948966;
PyHalfPiLo = 6.123233995736766e-17;
t := (t - q * PyHalfPiHi) - q * PyHalfPiLo;
```

Five shapes measured, four now **exactly** CPython, real parts included:

| | CPython | pxx before | pxx after |
| --- | --- | --- | --- |
| `(-4) ** 0.5` | `(1.2246467991473532e-16+2j)` | `(-0+2j)` | **exact** |
| `(-4+0j) ** 0.5` | same | `(-0+2j)` | **exact** |
| `complex(-4,0) ** 0.5` | same | `(-0+2j)` | **exact** |
| `(-1) ** 0.5` | `(6.123233995736766e-17+1j)` | `(-0+1j)` | **exact** |
| `(-8) ** (1/3)` | `1.0000000000000002+1.732…772j` | `1+1.732…767j` | real exact, imag ~4 ulp |

`PyCxCosSin` has exactly one caller, so the blast radius is complex `**` alone.

## The test's expectation was a DELIBERATE divergence the feature retired

The stale `.expected` was not an oversight. The test's own comment said so:

> *CPython answers the first with a COMPLEX, which this language does not have —
> so ValueError, deliberately, and recorded in nilpy-semantics-divergences.md.*

`feat(N): Python's complex type` gave NilPy a complex type and thereby retired a
*documented* divergence, leaving the test asserting a refusal that no longer
exists. (The divergences doc itself carries no such entry, so nothing was stale
there.) That block is rewritten to pin what actually changed — that a negative
base with a fractional exponent now returns a complex — asserted through
`type(z).__name__` and `round(z.real/z.imag, 12)`, which match CPython exactly.

Asserting 12 decimals rather than the repr is deliberate and stated in the test:
the last bits of the magnitude track whichever `pow`/`ln`/`exp` each side uses,
and pinning them would be pinning libm, not `**`.

## Verified

The whole test file is now byte-identical to `python3` on the same source;
`.expected` re-recorded from **CPython**, not from pxx. `tools/gate.sh quick`
GREEN, self-host fixedpoint converged.

## Split out, not folded in

- [[bug-n-pylib-cannot-reach-the-rtl-power-so-complex-magnitude-loses-ulps]] —
  the residual ulps. pylib is in `compiler/builtin` and cannot see the RTL's
  correctly-rounded `Power`, which is *why* it carries its own series ln/exp.
  Fixing it properly means moving a boundary the self-host bootstrap depends on;
  writing a third `pow` inside pylib would be the wrong trade.
- [[bug-n-abs-of-a-complex-raises-typeerror]] — found while writing the
  assertion. `type()`, `.real`, `.imag` and `round()` on a complex all match
  CPython; `abs()` raises `TypeError: expected a number, got object`.

## Note on the pin

The fix is in `compiler/builtin/pylib.pas`, so a program built with the PINNED
binary keeps the old `-0` until the next pin. The test builds with `$(COMPILER)`
and is green now. Not pinning unilaterally — a pin holds the repo lock for every
lane and the human, and nothing is waiting on this.

## Log
- 2026-08-16 — resolved.
- 2026-08-16 — resolved, commit PENDING-COMMIT.
