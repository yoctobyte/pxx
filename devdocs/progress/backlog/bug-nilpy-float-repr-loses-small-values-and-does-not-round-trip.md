---
track: N
prio: 20
type: bug
---

# `print(1e-20)` prints `0.0` — NilPy's float repr has no small-magnitude exponential form

```python
print(1e-20)     # CPython: 1e-20    pxx: 0.0
print(1e-300)    # CPython: 1e-300   pxx: 0.0
print(1.23e18)   # CPython: 1.23e+18 pxx: 1230000000000000000.0
print(-0.0)      # CPython: -0.0     pxx: 0.0
print(1/3)       # CPython: 0.3333333333333333  pxx: 0.333333333333333
print(0.1+0.2)   # CPython: 0.30000000000000004 pxx: 0.3
```

The first two destroy the value: a small but nonzero number renders as zero,
with no error. The rest are repr-fidelity divergences.

## Root cause

`compiler/builtin/builtin.pas`, `FloatToStr` (≈633) — NilPy's renderer, and a
DIFFERENT implementation from `lib/rtl/sysutils.pas`'s (see
[[bug-rtl-floattostr-caps-at-six-decimals-and-zeroes-small-values]], which has
the same hole at 6 places instead of 15):

```pascal
  intpart  := Trunc(v);
  fracpart := Round(Frac(v) * 1000000000000000.0);   { scale fractional part to 15 digits }
```

Fifteen DECIMAL places. `1e-20` has `intpart = 0` and rounds `fracpart` to 0,
so the result is `0.0`. There IS an exponential path (`FloatToExpStr`) but only
the LARGE guard reaches it:

```pascal
  if (v > 9.2e18) or (v < -9.2e18) then begin Result := FloatToExpStr(v); Exit; end;
```

Nothing routes small magnitudes there — the mirror-image guard is simply
missing. `-0.0` is lost separately: `neg := v < 0` is False for negative zero,
so the sign never gets re-attached.

## What CPython actually does

`repr(float)` is the SHORTEST string that round-trips to the same double,
rendered in exponential form when the decimal exponent is `< -4` or `>= 16`.
That is why `0.1+0.2` shows `0.30000000000000004` (17 digits needed) while
`2.5` shows `2.5` (2 suffice). pxx's fixed 15 decimal places can neither
round-trip the hard cases nor stay short on the easy ones — though in practice
it agrees with CPython on most ordinary values, which is why only the extremes
show up.

## Suggested split — do the value loss first, alone

1. **Small-magnitude exponential guard.** Add the mirror of the existing large
   guard so a value below the fixed window goes to `FloatToExpStr`. This is
   the only change that stops information being DESTROYED, and it leaves every
   normal-range float's output byte-identical — so the blast radius across
   recorded test expectations is nil. Fix `-0.0` in the same patch (test the
   sign bit, not `v < 0`).
2. **Exponential switch at >= 1e16**, to match CPython's threshold rather than
   the current 9.2e18 (which is the Int64-saturation boundary, not a Python
   rule). This DOES change output for values in between, so it wants its own
   gate run.
3. **Shortest-round-trip digits.** The real repr rule, and the largest change:
   it needs a Grisu/Ryu-style shortest-digit algorithm, not a scale-and-trim.
   Worth its own ticket and probably not worth it until something needs exact
   round-tripping.

## Gate

`make test-nilpy` + self-host byte-identical, plus a `.npy` covering the table
above with CPython's own output as the expectation. For step 1 specifically,
confirm that a normal-range sweep (0.5, 2.5, 100.0, 1/3, 1234567890.12345) is
byte-identical BEFORE and after — that is the evidence the change is confined
to the values that were broken.

## Priority note 2026-07-30 (user)

Float REPRESENTATION divergence is explicitly low value here: a mantissa
landing on `9.999999999999995e+299` instead of `1e+300` is not considered a
bug worth chasing. What DOES matter is honouring an explicitly REQUESTED
number of decimals (`%.15f`, `{:.3f}`, `FloatToStrF(v, n)`) — those paths are
a contract, and they currently test correct. Deprioritised accordingly; the
value-LOSS half (a nonzero number printing as `0`) is the part that was worth
fixing and is done for the NilPy renderer.

## Also in this family (found later, same low priority)

`print(1e308 * 10)` prints `Inf`; CPython prints `inf` (lower case). One word,
but NOT a one-word fix: the spelling comes from `FloatToStr` in
`compiler/builtin/builtin.pas`, which the PASCAL frontend also uses, and there
`Inf` is the FPC-correct spelling. So it needs a NilPy-specific rendering path
rather than an edit to the shared routine — which is more machinery than the
divergence is worth on its own. Fold it into whichever change gives NilPy its
own float repr (step 3 above).
