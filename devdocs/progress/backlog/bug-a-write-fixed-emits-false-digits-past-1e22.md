---
summary: "SILENT: write(v:w:d) prints digits that are not the value's digits once |v| > 1e22 — the integer part is expanded in Double arithmetic, so past 2^53 it leaks binary granularity (2^31, 2^47) into decimal output. Looks like extra precision, is noise"
type: bug
track: A
prio: 60
---

# `write(v:w:d)` prints false digits past 1e22

- **Type:** bug — **SILENT wrong output**. Track A (builtin float formatting).
- **Opened:** 2026-08-06, reviewing
  [[decide-float-fixed-output-exact-or-fpc-17-digit-cap]] with the user, whose
  question — "the description seems to be that we render a float *better*?" —
  is what exposed it. We do not render it better. We render it wrong.

## Measured against the exact value of the double

    1e15 .. 1e22   correct
    1e23   pxx 100000000000000000000000          exact 99999999999999991611392
    1e25   pxx 10000000000000002147483648        exact 10000000000000000905969664
    1e27   pxx 1000000000000000137438953472      exact 1000000000000000013287555072
    1e30   pxx 1000000000000000140737488355328   exact 1000000000000000019884624838656
    1e300  pxx 99999999999999983567616651958...  exact 10000000000000000525047602552...

1e22 is the largest power of ten exactly representable as a double, and that is
exactly where it breaks.

Two distinct wrong shapes, both silent:

- **binary granularity leaking into decimal** — `...2147483648` is 2^31,
  `...140737488355328` is 2^47. Those are artifacts of the algorithm, printed
  as if they were digits of the number;
- **the decimal literal echoed back** — 1e23/1e24/1e28/1e29 print
  `1000...000`, i.e. what the user typed rather than what the double holds.

At 1e300 it is wrong from the **first significant digit** (9.99... vs 1.00...).

## Cause

`PXXWriteFloatFixed` generates the integer part in `Double` arithmetic:

    var x, pw, v, ip, rem, dv, r, two52, ipc: Double;
    while ipc >= 10 do begin ipc := ipc / 10; ndig := ndig + 1; end;
    d  := Trunc(rem / dv);
    dv := dv / 10;

Beyond 2^53 a double cannot represent consecutive integers, so dividing down by
powers of ten cannot recover decimal digits — each division rounds, and the
rounding shows up as the powers of two above.

## This is fixable exactly — the machinery already exists

`PxxSciDigits17` in the same unit expands a double **exactly**, using base-10^9
integer limbs (`PXX_SCI_LIMBS`, `PXX_SCI_BASE`), because a double is
`mantissa * 2^exp` with both parts integral — an exact decimal expansion always
exists and needs only integer arithmetic. The scientific path uses it and is
correct; the fixed path does not.

So "print the exact value" is not aspirational, it is a matter of routing the
fixed path through the same limb expansion rather than through `/ 10` on a
Double.

## Relationship to the decision it came from

[[decide-float-fixed-output-exact-or-fpc-17-digit-cap]] was filed on the premise
that pxx prints the exact expansion and FPC prints a 17-digit approximation, and
asked which to prefer. **That premise was false** and the framing has to change:
today pxx prints *false precision*, and FPC's cap is defensible precisely
because the extra digits do not exist. The policy question survives, but only
after this is correct.

Also corrects a claim I wrote into
`compat-pascal-write-fixed-huge-magnitude-differs-from-fpc` on 2026-08-05 —
"pxx prints the true value, FPC prints its own approximation". The first half
was wrong and unverified; I compared the two implementations against each other
and never against the exact value.

## Not a regression, but the shape changed

The huge-magnitude fixed path was already wrong before this session — the
original ticket describes x86-64 saturating at Int64 with
`9223372036854775809.00000`. Replacing the four hand-written backend emitters
with one shim removed the saturation and made the targets agree, which was real
progress, but it left the digits wrong and I described the result as an exact
expansion.

## Gate

`write(v:0:d)` matches the exact decimal value of the double for magnitudes
past 2^53 on every target (oracle: Python `decimal.Decimal(float(x))`), or —
if [[decide-float-fixed-output-exact-or-fpc-17-digit-cap]] chooses a cap —
emits only digits it can justify and zeros beyond, never binary artifacts.
