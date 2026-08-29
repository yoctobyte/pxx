---
track: A+S
prio: 45
type: bug
status: open
found: 2026-08-29
found-by: frankD
summary: "`'zzz' < 'aaa'` on xtensa compares the two heap HANDLES as signed ints and answers by allocation order. This is the exact defect PXXStrCmp3 was added to fix — it was applied to i386/aarch64/arm32/riscv32 and xtensa was not visited, and the helper's own comment says 'the four cross backends' when there are five."
---

# xtensa has no ordered string compare: `a < b` sorts by heap handle

Found by the invariant sweep
([[audit-a-a-comment-asserting-an-invariant-is-a-claim-about-a-sibling-arm-nobody-checked]])
working the `builtinheap.pas` seam
([[audit-a-builtinheap-invariants-x86-64-inlines-past]]). It is the audit's shape
exactly: a fix applied to the arms someone had open, with the fifth arm never
visited, and a comment that counts the arms wrong.

## What is wrong

`compiler/ir_codegen_xtensa.inc:1622` guards the managed-string compare arm on
equality only:

```pascal
if ((op = Ord(tkEq)) or (op = Ord(tkNeq))) and
   ((IntToTypeKind(IRTk[left]) = tyAnsiString) or (IntToTypeKind(IRTk[right]) = tyAnsiString)) then
```

`<`, `<=`, `>`, `>=` on an `AnsiString` therefore fall past it into the generic
integer arm at `ir_codegen_xtensa.inc:1755`:

```pascal
else if op = Ord(tkLt) then
  EmitAsmXtensa(['movi a4, 1','blt a2, a3, .done','movi a4, 0','.done:','mov a2, a4'])
```

`a2` and `a3` hold the two **handles**. So the comparison is a signed 32-bit
compare of two heap pointers, and the answer is allocation order.

`FindProc('PXXStrCmp3')` appears in `ir_codegen386.inc`,
`ir_codegen_aarch64.inc`, `ir_codegen_arm32.inc` and `ir_codegen_riscv32.inc`.
It does **not** appear in `ir_codegen_xtensa.inc`.

## This is the same defect, re-created by omission

`PXXStrCmp3`'s own header records the original:

> *"the four cross backends had NO ordered-string arm at all ... `a < b` fell
> through to the ordinary integer compare and compared the two heap HANDLES ...
> `'zzz' < 'aaa'` reported by allocation order"*

**There are five cross backends.** The sentence names four and the fix covered
those four. The word "four" is the whole finding: it reads as a complete
enumeration, so nobody counted.

## Evidence

Measured at `e7385984b` with the pinned compiler
(`stable_linux_amd64/default/pinned`), no rebuild.

```pascal
program strord;
var a, b: AnsiString;
begin
  a := 'zzz';
  b := 'aaa';
  if a < b then WriteLn('WRONG: zzz < aaa') else WriteLn('ok: zzz >= aaa');
  if b < a then WriteLn('ok: aaa < zzz') else WriteLn('WRONG: aaa >= zzz');
end.
```

| target | result |
| --- | --- |
| x86-64 native | `ok: zzz >= aaa` / `ok: aaa < zzz` |
| riscv32 under `qemu-riscv32` | `ok: zzz >= aaa` / `ok: aaa < zzz` |
| xtensa under `qemu-xtensa` | **could not run — see below** |

**I could not demonstrate the wrong output, and I am not going to claim I did.**
Hosted xtensa does not currently run: `program hello; begin WriteLn('hi'); end.`
built with `--target=xtensa --platform=posix` **hangs** under `qemu-xtensa`
(killed at 120s), and the `strord` binary above dies with `uncaught target signal
7 (Bus error)`. That is a separate problem — hosted xtensa is still the open
[[feature-a-hosted-xtensa-so-qemu-xtensa-can-be-an-oracle]] — and it is also the
reason this bug survived: **the target has no working oracle, so the defect could
not surface as a red.**

What *is* measured, and is enough on its own:

- the guard and the fallthrough above, read directly;
- `PXXStrCmp3` is called by four backends and not by xtensa (grep, comments
  stripped);
- **code size moves the wrong way.** Same program with `=` vs with `<`:

  | target | `=` | `<` | delta |
  | --- | --- | --- | --- |
  | riscv32 | 242244 B | 242248 B | **+4** — both go through the helper |
  | xtensa | 213020 B | 212968 B | **−52** — the ordered form is *cheaper*, because it drops the whole decompose-and-call sequence for five instructions of integer compare |

  A correct ordered compare cannot be 52 bytes smaller than an equality compare.
  That number is the defect.

## Fix

Widen the `ir_codegen_xtensa.inc:1622` guard to the ordered operators and lower
them to `PXXStrCmp3(lenA, srcA, lenB, srcB)` -> -1/0/1, then map the result to
0/1 per operator — the shape `ir_codegen_riscv32.inc` already has, and the
operand decompose right below the guard is already written and reusable.

While there, fix `PXXStrCmp3`'s header comment to say **five**, or better, to
stop counting: *"the cross backends that do not call this helper have no ordered
string compare at all"* is the durable form, because it stays true when a sixth
target lands.

## Gate

Track A file ownership on `ir_codegen_xtensa.inc`; Track S by subject.
`make compiler/pascal26` (self-host byte-identical — x86-64 is untouched) plus
the `strord.pas` repro above cross-compiled and, when hosted xtensa runs, exercised
under `qemu-xtensa`. Until then the size delta is the check: after the fix, xtensa's
`<` must be **larger** than its `=`, not 52 bytes smaller.

## Note for whoever takes it

Check `>=`/`<=`/`>` too, and check the frozen-`tyString` and `Char` operand
shapes, not just handle-vs-handle — the equality arm handles three operand
shapes and the ordered arm will need the same three.
