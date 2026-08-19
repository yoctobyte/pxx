---
track: B
prio: 25
type: feature
blocked-by: []
summary: "ExBinNearest's big-integer primitives use 32-bit limbs because a limb times a sub-2^31 multiplier is the largest product that fits a signed Int64. MulHiU64 is already in lib/rtl/wideint.pas (intrinsic via IR_MULHI, already used by Eisel-Lemire in this same unit), so 64-bit limbs are available: half the limb count, BigFMulU64's five passes collapse to one, and the power-of-five chunk rises from 5^13 to 5^27. Expect ~4x, taking subnormal StrToFloat from ~8-11 us to ~2-3 us — inside CPython's range. A rewrite of six leaf routines with no change to the algorithm above them."
owner: frank3-etree
status: done
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

## 2026-08-19 (frank3-etree) — done. 1.6-1.8x, not the ~4x this ticket predicted.

Built and measured on pin **v356** (`2bb09afb0cff`), `-O2`. The prediction above
is **not met** and is recorded as unmet rather than reframed; the change still
earns its place, but on different grounds than the ones it was filed on.

### What changed

Base 2^64 over `UInt64` limbs. Carry *out* of a multiply is `MulHiU64`'s high
half; carry *in* is detected by the sum coming out below an addend. Limbs are
unsigned, and that is load-bearing rather than stylistic — the same code over
`Int64` would compare and shift signed, and a limb with its top bit set is the
common case here, not a corner. `PXX_BIGF_LIMBS` 224 -> 112, same 7168 bits, so
`ExBinNearest`'s capacity note is unchanged. Chunks rose 5^13 -> 5^27 and
10^9 -> 10^18.

### Scope shrank from six leaf routines to five, for a structural reason

`BigFMulU64` collapsed to a one-line forward to `BigFMulSmall`: its
split-into-two-halves-and-add existed *only* to respect the sub-2^31 cap on a
base-2^32 multiplier, and that cap is what this change removes.

**`BigFAdd` then had no callers at all and was deleted** (30 lines). It was
found by the perturbation table rather than by reading: removing its carry
detection entirely changed nothing across all 112,207 values, because the
routine was unreachable. The lesson is worth more than the deletion —
**a perturbation that passes is not automatically a weak oracle; first ask
whether the code you perturbed is reachable.** "The test did not catch it" and
"there was nothing to catch" are identical in the result column and have
opposite fixes: strengthen the test, versus delete the code.

So the artifact and everything downstream of it went together, which is why the
ticket got *smaller* while doing more.

### The oracle was proved able to fail

| perturbation | result |
| --- | --- |
| 5^27 off by one | caught — mismatches from the first rows |
| multiply carry-detect removed | caught — mismatches |
| shift carry dropped | caught — mismatch, and the search stopped converging |
| add carry-detect removed | **passed — `BigFAdd` was dead. Routine deleted.** |
| digit chunk 18 -> 17 | **passed — and the perturbation was INVALID.** |
| digit chunk: `p` desynchronised from the digits consumed | caught — mismatches |

Two of the five passed, for two *different* reasons, and neither reason was
"the oracle is weak":

- `BigFAdd`'s carry: the code was **unreachable**. Fix = delete the code.
- `chunk 18 -> 17`: `p` is computed as 10^chunk inside the same loop, so 17 is a
  **valid alternative chunking**, not a defect. I had perturbed a free
  performance parameter and called the result behaviour. Fix = perturb something
  that is actually load-bearing — desynchronising `p` from the digits consumed,
  which is caught immediately.

So the rule from the dead-code case needs a second clause. Before concluding a
passing perturbation means a weak test, ask **both**: is the code reachable, and
did I actually change behaviour rather than a free parameter? A perturbation
table is only evidence if each row would have been wrong; a row that merely
picks a different valid configuration proves nothing and reads exactly like a
row that does.

### Results — same harness, same pin, interleaved

Old and new were run **alternately, min-of-4 per row**, rather than back to back
on a quiet box. This box is shared and load sits near 1.8 from other lanes, so
*comparability* is what the measurement needs, not silence — waiting for a quiet
box that may never come is the worse method. Two hazards this does NOT cover,
both recorded because one of them nearly landed:

- **A pin mid-run breaks an A/B regardless of load management**, because both
  arms build with `$(PXX_STABLE)` and a pin replaces it — the two arms would be
  compiled by different compilers and the result would look clean. Handled by
  recording `md5sum stable_linux_amd64/default/pinned` (`540956f1f071...`,
  VERSION 356) **before** the run and re-checking it after; discard on mismatch.
  A recorded hash beats a coordination promise, because it also protects runs
  taken when nobody is coordinating.
- **A stale binary from an earlier session.** A leftover `bench_new` ran and
  printed plausible rows after the compile that should have produced it had
  *failed* — `cmd 2>&1 | tail -1 && ./bin` runs `./bin` regardless, since a
  pipeline's status is `tail`'s. Caught only because its row labels did not
  match the source just written.

| value | limb ops 32->64 | work | ns 32->64 | gain |
| --- | --- | --- | --- | --- |
| `1211563e-314` | 894 -> 410 | 2.18x | 11013 -> 6576 | **1.67x** |
| `81210348e-317` | 975 -> 446 | 2.19x | 11220 -> 6975 | **1.61x** |
| nd=40 `e-340` | 1210 -> 491 | 2.46x | 15159 -> 8612 | **1.76x** |
| `4e-323` | 825 -> 512 | 1.61x | 7665 -> 7481 | 1.02x |
| `4.94e-324` | 578 -> 377 | 1.53x | 6226 -> 5830 | 1.07x |
| every Clinger / Lemire row | not reached | — | 626-764 | **1.00x** |

Nothing on the fast paths moved, as scoped. All subnormal rows were confirmed to
actually reach `ExBinNearest` (`bin=1, dec=0` on an instrumented build), so the
comparison is like-for-like rather than an accident of which path answered.

### Why ~4x was wrong — a counting error, not a measurement one

A limb-operation counter, not a story: work fell **2.2x**, not 4x. Fitting the
two heavy rows gives **~9.2 ns per limb operation and a fixed ~2.8 us per
parse**, and that ~2.8 us independently reproduces the 2.5-3.5 us of setup this
ticket measured a different way, so the model is not fitted to itself.

The prediction listed three effects — half the limbs, five passes becoming one,
half the pow5 rounds — and multiplied them. **They are not three effects; they
are three descriptions of one quantity.** Compounding them was double-counting,
and it was persuasive precisely because each individual claim was true.

> When several improvements all reduce the same underlying quantity, they do not
> multiply — and a list of independent-sounding mechanisms is exactly what makes
> them look like they do. Count the quantity; do not enumerate the reasons it
> should drop.

### For anyone chasing the next 2x

**~2.8 us per parse is fixed setup that no limb-width change can touch** — which
is exactly why the two smallest-operand rows barely moved. The limbs are close to
done; the setup is where the remaining time is. Do not file another limb ticket.

### Gate

`make lib-test` **green** on pin **v357** (`ebcf15ccb1046b29353b3b85091a8cdc`,
captured before the run and re-checked unchanged after), including the
112,207-value CPython differential (`StrToFloat matches CPython on 112207
values`) and the roundtrip suite.

The benchmark rows above were taken on **v356** (`540956f1f071...`), hash
captured before and re-checked after. That is a *different pin from the gate's*,
and it is stated rather than blurred: the pin moved twice between the two runs
(a bad v357 was pinned, reverted, fixed and re-pinned —
[[bug-n-pin-v357-breaks-tk-nilpy-callable-value-of-a-def-with-no-signature-record]]).
The numbers were not re-taken on v357 because nothing in that pin touches
`sysutils.pas` or the float path; if anyone needs them on one pin, re-run the
interleaved A/B rather than trusting this note.

The ~2.8 us fixed-setup finding is recorded in the parent ticket
[[bug-b-strtofloat-is-3600x-slower-than-cpython-for-small-exponents]] as well as
here — it is the number that redirects the next optimiser, and it is invisible
sitting only in a resolved follow-up.

## Log
- 2026-08-19 — resolved, commit PENDING-COMMIT.
