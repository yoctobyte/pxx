---
track: A
prio: 30
type: compat
blocked-by: []
summary: "FPC unmasks the FP exceptions every ISA leaves masked: 1/0 is a runtime error there and Inf here, and Floor(1e30) raises EInvalidOp where pxx now saturates. Decided that pxx keeps IEEE masked semantics by default and FPC's behaviour goes behind opt-in flags — TWO of them, because div-by-zero -> runtime error 208 is nearly free (an FPU control word bit) while Floor raising EInvalidOp costs sysutils, +127 KB code and +33 KB bss on every `uses math` program."
---

# `--strict-fpc`: unmasking FP exceptions, as TWO flags

- **Type:** compat (FPC parity behind a flag) — **Track A** (the FPU control
  word and the flag plumbing are core; the `math` half is a Track B branch
  behind whatever the flag ends up being called).
- Follows directly from
  [[decide-may-uses-math-cost-the-heap-and-exception-runtime]] (decided
  2026-08-14, commit `87ecef258`), which set the default — **saturate, do not
  raise** — and said the FPC behaviour belongs behind an opt-in flag. The
  default half is landed in `lib/rtl/math.pas`
  ([[bug-b-floor-of-an-out-of-range-double-returns-0-where-fpc-raises]]); this
  is the opt-in half.

## The divergence, measured

Same x86-64 machine, same program:

| | `1/0` | `0/0` | `Floor(1e30)` | exit |
| --- | --- | --- | --- | --- |
| pxx | `Inf` | `Nan` | `2147483647` (saturates) | 0 |
| FPC | — | — | `EInvalidOp` | **Runtime error 208** |

IEEE-754 specifies *flags*, not traps, and x86, ARM, RISC-V and Xtensa all leave
FP exceptions masked. FPC deliberately unmasks them. So this is one runtime's
policy, not hardware behaviour, and reproducing it is opt-in work.

## Why TWO flags and not one

The two halves differ by orders of magnitude in cost, and lumping them makes the
nearly-free one carry the expensive one's baggage:

| behaviour | mechanism | cost |
| --- | --- | --- |
| FP div-by-zero → runtime error 208 | unmask the FPU control word | ~free; **no exception machinery** — a runtime error is not an exception, which is Pascal's own behaviour when exceptions are absent |
| `Floor`/`Ceil` raise `EInvalidOp` | `uses sysutils` in `math` | **+127 KB code, +33 KB bss** on every `uses math` program (52/9.5 bare → 123/9.5 with math → 251/42.7 with math+sysutils) |

The second also cannot compile today without a Track A change: a heap-free
program that says `uses math` fails with `array of const requires the
builtinheap unit`, because `DetectPascalRuntimeNeeds` (`compiler/parser.inc`
~32833) prescans the **program** for `needHeapUnit` and cannot see a need
introduced by a unit's *implementation*-uses. Whether that prescan gap is worth
fixing on its own merits is a fair question — it looks latent and general.

Putting the `uses` in `math`'s **interface** instead is not an escape: pxx's
`uses` is transitive ([[bug-pascal-uses-is-transitive]]) and `pxxcio` does `uses
math`, so every sysutils name would enter scope for every C program — the exact
hijack `lib/rtl/math.pas`'s own header records as having shipped broken once.

## Umbrella enrolment is a separate call

`--strict-fpc` is documented as *"proven to compile the real FPC corpora — fgl,
Synapse, fpjson 203/203"*. A member that drags sysutils into `math` changes what
the umbrella costs for all of them, so enrolment must be decided with those
corpora re-checked. **There is precedent for saying no:** `StrictOverload` is
deliberately excluded and kept standalone. Landing each flag standalone first is
the safe order. Same reasoning applies to
[[compat-pascal-strict-fpc-should-pick-the-narrowest-integer-overload]].

## Gate

With the flag off, every row of the current behaviour is unchanged and
`test/test_math.pas` still compiles heap-free. With it on, the FPC column above
is reproduced. `make test` + self-host fixedpoint; the corpora `--strict-fpc`
already compiles stay green, whether or not the flag is enrolled in the
umbrella.

<!-- float category -->
Indexed on [[meta-float-accuracy-policy]] — the standing float-accuracy index.
Collect, do not fix piecemeal; see the working rule there.
