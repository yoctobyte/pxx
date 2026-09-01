---
slug: bug-a-emitloadvar-truncates-a-dynarray-handle-to-its-element-width
title: "EmitLoadVar loads a dyn-array handle at the ELEMENT's width, sign-extending"
track: A
prio: 40
type: bug
status: done
found: 2026-09-02
found-by: frankB
owner: ""
blocked-by: []
summary: "`AllocDynArray` sets `Syms[].TypeKind := elemType`, so a dynamic array symbol's TypeKind IS its element kind. `EmitLoadVar` (symtab.inc:5400) opens `tk := Syms[idx].TypeKind; sz := TypeSlotSize(tk); sgn := TypeSigned(tk)` with NO IsArray check on that path, so any `IR_LOAD_SYM` reaching a dyn-array symbol loads the 8-byte HANDLE at the element's width and sign-extends it — an `array of Integer` handle came back as 0xffffffffe7e00020. Nothing rejects it, it is silent, and it is element-type-dependent: pointer-sized element kinds (AnsiString, class, nested array) are correct by accident, so the failure looks like 'works for strings, segfaults for integers'. 64-bit only — on i386/arm32/riscv32 a handle is 4 bytes and the wrong width is the right one. No CURRENT caller is broken (the handle read everywhere else is IR_LEA), so this is a trap for the next one, not a live wrong answer."
---

# EmitLoadVar truncates a dyn-array handle to its element width

## How it was found

Not by reading the code. `IRParkManagedDyn` ended with `IRAppend(IR_LOAD_SYM,
pdSym, ...)` tagged `Ord(tyPointer)`, which is what made this invisible: the IR
tag says pointer, and an IR dump of the integer and string cases is
structurally identical. The width does not come from the tag.

It cost about a day, spread over two sessions, and produced five refuted
hypotheses in
[[bug-a-a-fresh-array-result-has-no-owner-as-a-copy-or-concat-operand]] before
the faulting instruction gave it away:

```
mov %r14,%rax ; add $0x0,%rax ; sub $0x8,%rax ; mov (%rax),%rax   <-- SIGSEGV
rax = 0xffffffffe7e00018
```

`0xffffffff...` is a sign-extended 32-bit value, not a heap address.

## The mechanism

```pascal
{ symtab.inc, AllocDynArray }
Syms[SymCount].TypeKind := elemType;    { <-- the ELEMENT kind }
Syms[SymCount].IsArray  := True;
Syms[SymCount].ArrLen   := -1;
```

```pascal
{ symtab.inc:5400, EmitLoadVar }
tk  := Syms[idx].TypeKind;
sz  := TypeSlotSize(tk);
sgn := TypeSigned(tk);
```

`array of Integer` → `sz=4, sgn=True` → a 4-byte sign-extending load of an
8-byte handle.

Note `IR_LOAD_SYM`'s call-arg loadability helper in ir_codegen.inc DOES check
`Syms[si].IsArray` and treat `ArrLen = -1` as "a plain pointer read". So one
side of this already knows a dyn-array handle is pointer-sized and the other
does not — two mechanisms serving one concept, which is the smell
`normalise-dont-special-case` names.

## Why nothing is broken today

Every handle read in the tree goes through `IR_LEA`, which is the correct
idiom and has no such dependence. The park was the one caller that used
`IR_LOAD_SYM` on an array symbol, and it has been changed to `IR_LEA`.

So this is a **guard that does not exist**, not a live wrong answer: the next
caller to reach an array symbol through `IR_LOAD_SYM` gets a silently truncated
pointer on 64-bit only, and will spend the same day.

## Shape of a fix

In `EmitLoadVar`, before the width is taken:

```pascal
if Syms[idx].IsArray and (Syms[idx].ArrLen = -1) then
begin tk := tyPointer; sz := TypeSlotSize(tyPointer); sgn := False; end;
```

Cheap, and it can only turn a wrong width into a right one — no current caller
depends on the truncation, because a truncated handle is never useful. But
`EmitLoadVar` is a hot shared path on every backend, so it wants its own
landing and its own gate rather than riding along with the leak fix.

Worth checking in the same pass whether the other backends' load emitters
(`EmitLoadVarA64`, `EmitLoadVarArm32`, `EmitLoadVarXtensa`, riscv32) have the
same shape. They are 32-bit or have their own paths, so the bug does not BITE
there, but the missing check probably reads the same — and "fixed one arm of a
double case, grep for the sibling" applies.

## Log
- 2026-09-02 — resolved; this names the commit that carried the resolve, which is not always the one that carried the change — commit 32c15a95b.
