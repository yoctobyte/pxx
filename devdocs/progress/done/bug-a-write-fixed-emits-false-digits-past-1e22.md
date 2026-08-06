---
summary: "SILENT: write(v:w:d) prints digits that are not the value's digits once |v| > 1e22 — the integer part is expanded in Double arithmetic, so past 2^53 it leaks binary granularity (2^31, 2^47) into decimal output. Looks like extra precision, is noise"
type: bug
track: A
prio: 60
status: done
owner: claude-AB
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

## Log
- 2026-08-06 — resolved, commit PENDING-COMMIT.

## Resolution 2026-08-06

`PXXWriteUIntD` — the shared integer-part writer behind `PXXWriteFloatFixed`,
which every backend now shims onto — routes anything at or above 2^53 to a new
`PxxIntDDigits`, the exact base-10^9 limb expansion the file already carried
for the scientific path. Only the `exp2 >= 0` half of the expansion is needed:
a double at or above 2^53 is an integer times a power of two, so multiplying
the limbs by two IS the conversion. The field-width digit count goes through
the same routine, since `while ipc >= 10 do ipc := ipc / 10` is inexact for the
same reason and can land the count a column off.

    1e23   99999999999999991611392
    1e25   10000000000000000905969664
    1e27   1000000000000000013287555072
    1e30   1000000000000000019884624838656.00
    1e300  1000000000000000052504760255204420248704...

Every one matches `decimal.Decimal(float(x))`. Verified over **3000 random
doubles** (1e-8 to 1e100, `:0:0` through `:0:12`) against `decimal.Decimal`
quantized ROUND_HALF_UP: exact, and **byte-identical on x86-64, i386, arm32,
aarch64 and riscv32** — the whole corpus re-run under qemu on i386 and riscv32,
diff-clean against the native output. `test/lib_writefloat_fixed.pas` carries
the huge-magnitude cases (Makefile-checked, since `Chk` cannot reach them —
see below); `gate.sh quick` testmgr GREEN.

**Note on `gate.sh quick`'s fixedpoint leg.** It seeds from the PINNED binary,
which links the FROZEN `stable_linux_amd64/default/builtin/`, so generation A
carries the pre-change runtime and A != B for any `compiler/builtin/**` edit.
B == C byte-for-byte and `make compiler/pascal26` converges in one round — the
fixedpoint holds. It clears on the next `make pin`, which is not taken here
because Track B does not need this change.

Left open on purpose, both filed rather than guessed:

- the FRACTION past ~16 digits is still a Double-scaled approximation zero-
  padded past 18 — same defect class, other half of the number, now
  [[bug-a-write-fixed-fraction-digits-past-16-are-invented]] (prio 35: it only
  bites where no correct program can be relying on the answer);
- `Str(v:w:d)` and `WriteLn(v:w:d)` now DISAGREE past 9.2e18 — `StrFloat` hands
  that range to `FloatToExpStr` and answers `1e+23`. Noted on
  [[compat-pascal-write-fixed-huge-magnitude-differs-from-fpc]], which is
  blocked on [[decide-float-fixed-output-exact-or-fpc-17-digit-cap]]: *which*
  form to print past the Int64 range is exactly that parked decision, so
  routing StrFloat through the expansion waits for it.

The display-policy question is now answerable, which it was not while the
digits were wrong.
