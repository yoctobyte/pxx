---
track: A
prio: 65
type: bug
blocked-by: []
summary: "Arithmetic on a Variant holding a STRING reads the payload as a number instead of converting: `v('15') - w(3)` answers 139332782393069 — the AnsiString HANDLE, a heap address, as an integer. A one-character string answers its char ordinal ('5'-3 = 50). FPC converts the string (2) or raises EVariantError. Silent, and the wrong value is nondeterministic."
status: done
owner: frank1-ACP
---

# Variant arithmetic reads a string's payload as a number

- **Track A** (x86-64's `EmitVarBinOp` in `ir_codegen.inc`, and its twin
  `PXXVarBinOp` in `compiler/builtin/builtinheap.pas` which every other backend
  calls).
- Found 2026-08-20 by an FPC differential probe over Variants.

## The measurement

`fpc -O- -Mobjfpc` 3.2.2 vs pxx at `27232bed4`. Every row is a silent wrong
value — no error, no warning, and the multi-character rows print a heap address:

| operands | expression | FPC | pxx |
| --- | --- | --- | --- |
| `'5'`, `3` | `v + w` | 8 | **5** |
| `'5'`, `3` | `v - w` | 2 | **50** (Ord('5') - 3) |
| `'5'`, `3` | `v * w` | 15 | **159** (Ord('5') * 3) |
| `'15'`, `3` | `v - w` | 12 | **139332782393069** ← the AnsiString handle |
| `'15'`, `3` | `v * w` | 45 | **417998347179216** ← ditto, x3 |
| `3`, `'5'` | `v + w` | 8 | **5** |
| `3`, `'5'` | `v < w` | TRUE | **FALSE** |
| `'ab'`, `3` | `v + w` | EVariantError | **'ab'** |
| `'ab'`, `3` | `v * w` | EVariantError | **417998347179480** |
| `'5'`, `2.5` | `v + w` | 7.5 | **5** |
| `'5'`, `2.5` | `v * w` | 12.5 | **132.5** |
| `'5'`, `'3'` | `v * w` | 15 | **2703** (53*51) |
| `'x'`, `'y'` | `v - w` | EVariantError | **-1** |
| `'5'`, `'3'` | `v + w` | '53' | '53' — correct |
| `'x'`, `'y'` | `v + w` | 'xy' | 'xy' — correct |

Two distinct defects behind them:

1. **`+` with one stringy and one numeric operand DROPS the numeric side.** The
   dispatch takes the string/concat branch when EITHER side is stringy, and the
   concat only renders the stringy one — `'5' + 3` is `'5'`, `5 + '3'` is `'3'`.
2. **`-`, `*`, `/` never test for a string at all**, so the numeric path reads
   the variant payload directly: a char's ordinal for `VT_CHAR`, and the
   **AnsiString pointer** for `VT_STRING`. That is the address of heap memory
   appearing as an arithmetic result, so the answer changes between runs.

Comparisons are half right: `'5' = 3` is FALSE in both (FPC raises for a
non-numeric string, pxx answers FALSE), but `3 < '5'` is TRUE in FPC and FALSE
in pxx.

## What FPC does, and it is already written down here

FPC converts a string operand to a number, and raises `EVariantError` if it
does not parse. **pxx already implements exactly that rule** — in
`VariantToInt64` (`compiler/builtin/builtin.pas`), whose `VT_STRING` arm reads:

> *VT_STRING. FPC PARSES it -- measured, not assumed: `i := v` with v='42'
> yields 42 and v='abc' raises EVariantError.*

So `i := v` with `v = '42'` is right, and `v * 2` with the same `v` is a heap
address. The conversion rule exists; the binop path does not call it.

## Two mechanisms, and a fix has to land in both

- **x86-64** hand-emits the whole double-dispatch as assembly in `EmitVarBinOp`
  (~2400 lines of `ir_codegen.inc`).
- **i386, arm32, aarch64** call a Pascal helper, `PXXVarBinOp(dest, left, right,
  opTk, isCompare)` in `builtinheap.pas`, which reimplements the same dispatch
  in Pascal — and reimplements the same defects (its string arm likewise only
  fires for compare and `tkPlus`, and its mixed string/number compare returns
  "unequal, unordered" rather than converting).

Two mechanisms for one concept, so the obvious root-cause move is to delete one:
have x86-64 call `PXXVarBinOp` like every other backend. **Do not do that
blind.** The variant binop is NilPy's whole value model — the x86-64 asm carries
NilPy-specific behaviour (None equality ahead of every other dispatch, the
bitwise-on-non-integer raise) that the Pascal helper would have to reproduce
exactly, and `test-nilpy` is NOT in `gate.sh quick`, so a regression there would
not surface until Track T's next full tier.

## Containment that makes this landable

`PyProgramMode` is known at EMIT time. Gate the new coercion on `not
PyProgramMode` and NilPy's generated code is byte-for-byte what it is today,
with the Pascal path getting FPC's rule. That turns "rewrite the variant engine"
into "add an arm the Pascal path takes", and it is how this should start.

## Gate

`make compiler/pascal26` + self-host fixedpoint, `tools/gate.sh quick`, a new
test pinning every row of the matrix above against FPC 3.2.2 — **and**, because
of the NilPy exposure, `PXX_ALLOW_FULL_SUITE=1 make test-nilpy` once before
pushing, or an explicit hand-off to Track T with the sha.

---

## RESOLVED 2026-08-20 — `frank1-ACP` (Track A, sole-A confirmed)

Fixed by giving the numeric dispatch the conversion that already existed
elsewhere, not by rewriting the variant engine.

**`PXXVarNumCoerce(src, dst)`** (`compiler/builtin/builtin.pas`, next to
`VariantToInt64` whose rule it follows): a `VT_STRING`/`VT_CHAR` operand becomes
`VT_INT64` if the text parses as an integer, `VT_DOUBLE` if it parses as a real,
and otherwise halts with FPC's `EVariantError` wording. **Every other tag is
returned untouched**, which is what lets the emitter call it unconditionally on
both operands and keeps the change to one arm.

`EmitVarBinOp` (x86-64) calls it at the head of the numeric path, and — for
Pascal `+` only — now takes the concat branch when **BOTH** operands are stringy
rather than when either is. Two scratch variants plus the two saved operand
addresses live in one 48-byte BSS block allocated on first use; one shared block
is sound for the same reason the per-node result slot is (both operands are
fully evaluated before the binop runs, and the coercion helper cannot re-enter a
variant binop).

**NilPy is excluded at EMIT time** (`PyProgramMode`), not at run time, so its
generated code is unchanged: `'5' * 3` is still `'555'`, `'5' + 'x'` still
`'5x'`, `'5' + 3` still a TypeError, verified against CPython, and three variant
`.npy` tests still match their `.expected`. The emitter also skips the coercion
when `FindProc('PXXVarNumCoerce')` misses, so a program pulling no builtin unit
keeps the old behaviour instead of failing to compile.

### Result

`test/test_variant_string_arithmetic.pas` — 27 assertions, all `fpc -O-
-Mobjfpc` 3.2.2's: one-character and multi-character numeric strings on either
side, a Double on the other side (the pair promotes: `'5' + 2.5` is 7.5, not 7),
a fractional string, a negative string, both-stringy `+` still concatenating,
non-stringy pairs untouched, and the comparison rows. **The pinned binary scores
10/27.** Wired into `make test`; `tools/gate.sh quick` GREEN, self-host
fixedpoint byte-identical.

### What is NOT fixed, deliberately

- **Mixed-type COMPARISONS.** `3 < '5'` is TRUE in FPC and FALSE here — the
  compare arm answers "unequal, unordered" for a mixed pair rather than
  converting. It is a separate arm with its own FPC semantics (FPC raises
  `EVariantError` comparing a non-numeric string with a number), it is not
  silently corrupting the way the arithmetic was, and the test asserts today's
  answers so the day it changes the test says so.
- **The other backends.** i386/arm32/aarch64 route `IR_VAR_BINOP` through
  `PXXVarBinOp` in `builtinheap.pas`, which carries the same defect in Pascal
  form. Its signature has no language discriminator, so giving it the same rule
  is a separate change — filed as
  `bug-a-pxxvarbinop-carries-the-same-string-arithmetic-defect-as-x86-64-did`.
- **`EVariantError` is a halt, not a raise.** `VariantToInt64` already halts
  with a printed message rather than raising a catchable exception, and the new
  helper follows that convention rather than inventing a second one. FPC raises,
  so `try..except` around variant arithmetic on a non-numeric string still
  cannot catch it.
- **`writeln` of a whole-valued Double variant** prints `15.0` where FPC prints
  `15`. Measured identical on the pinned binary, so it predates this; it is
  float FORMATTING and therefore Track F — parked as
  `float/compat-pascal-a-whole-valued-double-variant-writes-a-trailing-point-zero`.

