---
track: A
prio: 45
type: bug
blocked-by: []
summary: "i386, arm32 and aarch64 route variant binops through PXXVarBinOp in builtinheap.pas, which reimplements the same dispatch x86-64 hand-emits — and the same defect: a stringy operand's payload is read as a number. x86-64 was fixed 2026-08-20; those three targets still answer a heap address for `v('15') - 3`."
status: backlog
owner: unassigned
---

# `PXXVarBinOp` still reads a string operand's payload as a number

- **Track A** (`PXXVarBinOp` in `compiler/builtin/builtinheap.pas`).
- Split out 2026-08-20 from
  [[bug-p-variant-arithmetic-on-a-string-reads-the-payload-as-a-number]], which
  fixed the x86-64 half.

## What is left

x86-64 hand-emits the variant binop dispatch in `EmitVarBinOp`; **i386, arm32
and aarch64 call `PXXVarBinOp(dest, left, right, opTk, isCompare)`** instead.
The Pascal helper reimplements the same double-dispatch — and the same two
defects the x86-64 arm had: its string arm fires only for compare and `tkPlus`
(so `-`, `*`, `/` read the payload raw), and for `tkPlus` it fires when EITHER
side is stringy while rendering only that side.

So on those three targets `v('15') - 3` is still a heap address and `v('5') + 3`
is still `'5'`. The x86-64 fix is `PXXVarNumCoerce` in `builtin.pas`, which is
ordinary Pascal and directly callable from `PXXVarBinOp` — the conversion itself
needs no porting.

## The one real obstacle

`PXXVarBinOp`'s signature carries no language discriminator, and the rule
differs: Pascal converts (`'5' * 3` is 15), Python repeats (`'5' * 3` is
`'555'`). x86-64 solves this at EMIT time with `PyProgramMode`, which a shared
runtime helper cannot see. Options, cheapest first:

1. **A global the frontend sets once** — a `PXXVarPascalRules` boolean in the
   runtime, initialised by the driver. One store at startup, no ABI change.
2. **A sixth parameter.** ABI change across three backends' call sites.
3. **Two helpers**, `PXXVarBinOpPas` / `PXXVarBinOpPy`, chosen by the emitter.

(1) is the small one and matches how the emitter already decides: once, per
program.

## Gate

Track A's, plus the cross targets: `test/test_variant_string_arithmetic.pas`
must pass under `--target=i386`, `--target=arm32` and `--target=aarch64`. Note
the i386 variant path has an unrelated problem to look at first — a variant
program with `try..except` around the arithmetic segfaults there at
`27232bed4`, before any of this.
