---
track: B
prio: 25
type: feature
blocked-by: []
summary: "ExBinNearest's big-integer primitives use 32-bit limbs because a limb times a sub-2^31 multiplier is the largest product that fits a signed Int64. MulHiU64 is already in lib/rtl/wideint.pas (intrinsic via IR_MULHI, already used by Eisel-Lemire in this same unit), so 64-bit limbs are available: half the limb count, BigFMulU64's five passes collapse to one, and the power-of-five chunk rises from 5^13 to 5^27. Expect ~4x, taking subnormal StrToFloat from ~8-11 us to ~2-3 us — inside CPython's range. A rewrite of six leaf routines with no change to the algorithm above them."
owner: unassigned
---

# `StrToFloat`'s big integers want 64-bit limbs

- **Type:** feature (performance) — **Track B** (`lib/rtl/sysutils.pas`).
- **Opened:** 2026-08-19, splitting the last remaining lever out of
  [[bug-b-strtofloat-is-3600x-slower-than-cpython-for-small-exponents]], whose
  gate is now met on every row it names. This is the residue, scoped by
  measurement rather than carried as a sixth pass on a resolved ticket.
- **Measured on:** pinned v355 (`739dfeb2d0e8`), `-O2`.

## Where the time actually goes — measured, three ways

`ExBinNearest` parses a subnormal in ~8-11 us. Not the step count, not the
buffer:

| question | how it was answered | answer |
| --- | --- | --- |
| too many comparisons? | counter in `BigFCmpValue` | **6** for a subnormal |
| buffer too big (copies/zeroing)? | rebuild with `PXX_BIGF_LIMBS` 224 -> 64 | 11.2 us -> 10.0 us, **13%** |
| setup or search? | return early after the setup | setup **2.5-3.5 us**, search the rest |

Six comparisons over ~26-limb operands at ~1.3 us each is **~8 ns per limb
operation**. That is the whole remaining cost, and it is the thing to attack.

(The counter matters: this ticket's parent recorded "a 63-step search" for two
passes before anyone counted, and it was 4. Count, do not read the header.)

## Why the limbs are 32-bit today

`BigFMulSmall`'s inner line is `t := a[i] * f + carry`. With base 2^32 limbs and
`f` under 2^31 that product cannot leave a signed Int64, which is what lets every
routine be plain Pascal with no 128-bit intermediate — including on 32-bit
targets. The cap on `f` is also why the power-of-five chunk is 5^13
(1,220,703,125, the largest power of five under 2^31) and why `BigFMulU64` has to
split its multiplier into two sub-2^31 halves and run **five passes** (copy, two
multiplies, a shift, an add) where one would do.

## The lever

`MulHiU64(a, b)` — the unsigned 64x64 -> 128 high half — is already in
`lib/rtl/wideint.pas`, intrinsic on 64-bit targets via `IR_MULHI` with a Pascal
fallback on 32-bit, and **already used in this same unit** by `EiselLemire`. So
64-bit limbs need no new primitive:

```pascal
  lo := limb * v;                 { low 64, wrapping }
  hi := MulHiU64(limb, v);
  t  := lo + carry;
  if t < lo then hi := hi + 1;    { unsigned carry detect }
  a[i] := t; carry := hi;
```

Three effects, each independent:

1. **Half the limbs.** A subnormal's operands go from ~26 limbs to ~13.
2. **`BigFMulU64` becomes one pass instead of five** — no splitting, no scratch
   copy, no add.
3. **5^27 instead of 5^13** per chunk in `BigFMulPow5`, halving the setup's ~25
   rounds. The setup is 2.5-3.5 us of the 11, so this alone is worth ~1.5 us.

Rough expectation **~4x**: subnormals at 2-3 us, which is inside the range
CPython measures on the same box (1.06-2.61 us; note that the parent ticket's
often-quoted 0.72 us does **not** reproduce and should not be used as the
target).

## The UInt64 arithmetic this needs was PROBED before the ticket was believed

Checked on pinned v355, so nobody has to find out mid-rewrite that the dialect
will not carry it. All eight answers correct:

| shape | pxx |
| --- | --- |
| `a[0] > a[1]` on a `UInt64` array, $FFFF... vs 1 | TRUE — unsigned, as needed |
| `$FFFFFFFFFFFFFFFF + 2` | 1 — wraps, does not trap |
| carry detect `t < x` after that add | TRUE |
| `MulHiU64($FFFF..., 2)` | 1 |
| `x * y` low half | 18446744073709551614 |
| `x shr 60` | 15 |
| `(UInt64(1) shl 63) shr 63` | 1 |
| `7450580596923828125` as a literal (5^27) | exact |

So `array[..] of UInt64` with wrapping add, unsigned compare and `MulHiU64` all
behave, and 5^27 fits a plain literal (it is under 2^63, so no `UInt64`-only
constant is needed anywhere). Digit chunks should stay at 18 (10^18 < 2^63) for
the same reason.

## Scope

Six leaf routines — `BigFMulSmall`, `BigFAddSmall`, `BigFAdd`, `BigFShl`,
`BigFMulU64`, `BigFCmp` — plus `BigFFromDigits`/`BigFMulPow5`'s chunk sizes and
the `PXX_BIGF_LIMBS` bound comment. **No change to `ExBinNearest` itself**, whose
algorithm, decline behaviour and search are independent of the limb width.

Watch for: unsigned comparison on Int64 limbs (`t < lo` must be unsigned — use
`UInt64`, as `EiselLemire` does in this unit), the 32-bit fallback path of
`MulHiU64` being the slow one, and `BigFShl`'s word/bit split moving from 32 to
64.

## Gate

Track B: build with `$(PXX_STABLE)`, never rebuild the compiler.

- `make lib-test` green — `test/lib_strtofloat_lemire.pas` (112,207 values
  diffed against CPython, including 12 exact midpoints) and
  `test/lib_strtofloat_roundtrip.pas` are both already in it and are the real
  constraint here.
- **Prove the oracle can fail before believing its zero.** The parent ticket's
  perturbation table is the model: an off-by-one in the power-of-five constant
  must produce tens of thousands of mismatches, and inverting the tie rule must
  fail the midpoint block. A change that makes the tests pass *faster* without
  that check is not verified.
- The benchmark rows in the parent ticket, re-run on the same pin, with the pin
  named.
