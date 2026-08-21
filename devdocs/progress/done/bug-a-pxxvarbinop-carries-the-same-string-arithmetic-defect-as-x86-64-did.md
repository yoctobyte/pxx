---
track: A
prio: 45
type: bug
blocked-by: []
summary: "i386, arm32 and aarch64 route variant binops through PXXVarBinOp in builtinheap.pas, which reimplements the same dispatch x86-64 hand-emits — and the same defect: a stringy operand's payload is read as a number. x86-64 was fixed 2026-08-20; those three targets still answer a heap address for `v('15') - 3`."
status: done
owner: claude-A
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

## Resolution (2026-08-21)

Fixed on all four targets that route through the helper. `test/test_variant_string_arithmetic.pas`
is **27/27 on native, i386, arm32 and aarch64** (it was 27/27 native and 2/27
on the other three: every arithmetic row answered a heap address).

### Option 3, not option 1

The ticket ranked "a runtime global the driver sets once" cheapest. It is not
— it is the same defect one level down. A global is *program* state, and the
thing being discriminated is a *call site*: the emitter already knows which
language it is lowering, at the exact moment it writes the call, and a global
throws that away and re-derives it at runtime from an initialisation the driver
must remember to perform. Nine frontends have now each forgotten a
driver-side initialisation step exactly once
([[bug-a-only-the-pascal-driver-emits-the-signal-runtime]] was that same shape,
this week), so the cheap-looking option is the one with a known failure mode.

So: **`PXXVarBinOpPas` in `builtin.pas`**, a thin wrapper that applies FPC's
rule and then calls the raw dispatch, and three backends that pick the helper
by name:

```pascal
if PyProgramMode then procIdx := FindProc('PXXVarBinOp')
else begin
  procIdx := FindProc('PXXVarBinOpPas');
  if procIdx < 0 then procIdx := FindProc('PXXVarBinOp');
end;
```

The wrapper is six lines of logic: coerce both operands through
`PXXVarNumCoerce` **unless** the op is `+` and both sides are stringy — the one
case that stays a concatenation — then hand the (possibly coerced) operands to
`PXXVarBinOp` unchanged. `PXXVarBinOp` remains the single definition of what an
operator *does*; the wrapper only decides what the operands *are*. That is the
same split x86-64 has, and it is why NilPy keeps the raw helper untouched.

An earlier attempt put the coercion in the three BACKENDS, hand-emitting a
`PXXVarNumCoerce` call before the dispatch on each. It was reverted: it is
three copies of one rule (the fourth being x86-64's), it got the i386 stack
offsets wrong on the first pass because the coercion block landed after
`push dest`, and it broke `'5' + '3'` because a backend cannot cheaply ask
"are BOTH sides stringy" at emit time. One Pascal wrapper answers that in a
line.

### The second defect, found by fixing the first

With real values finally reaching the arithmetic, i386 and arm32 came back
25/27 with `FAIL i-s: got [4294967294] want [-2]`. `PXXVarBinOp` read and wrote
the 16-byte slot's payload through `PWord`, which is `^NativeInt` — **pointer**
sized, so 4 bytes on a 32-bit target. Every negative operand and every negative
result was zero-extended.

That is pre-existing and independent of the string rule; it was invisible only
because the payloads reaching the numeric path were heap addresses, which are
positive. The double arm had already been patched around it once (it reads
through `PDouble` with a comment saying why) — the integer arm never was, which
is [[normalise-dont-special-case]]'s "the second path is the one that stays
broken" almost verbatim. Fixed by re-reading both payloads through `PInt64`
once the string arms are behind us, and writing the integer result the same
way.

### Not covered

**riscv32** still refuses the test at `IR_VAR_STORE` — `target riscv32:
unsupported node in IR codegen: var_store`. That wall is
[[bug-a-nilpy-on-cross-targets-four-remaining-walls]], not this ticket; when it
falls, riscv32 gets this fix for free, because it calls the same helper.

## Gate

`tools/gate.sh quick` GREEN (self-host fixedpoint 112s, testmgr quick), plus
the ticket's own repro: `test/test_variant_string_arithmetic.pas` 27/27 under
`--target=i386`, `--target=arm32`, `--target=aarch64` and native. Cross-target
breadth is Track T's, against this sha.

## Log
- 2026-08-21 — resolved, commit c937ad1e2.
