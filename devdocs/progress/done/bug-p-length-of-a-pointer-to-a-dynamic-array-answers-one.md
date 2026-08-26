---
slug: bug-p-length-of-a-pointer-to-a-dynamic-array-answers-one
title: "`Length(p^)` over a pointer to a named DYNAMIC array answers 1, and `High(p^)` answers 0"
track: P
prio: 50
type: bug
blocked-by: []
status: done
owner: ""
created: 2026-08-25
summary: "`PDyn = ^TDyn` with `TDyn = array of LongWord`: after `SetLength(d, 5)`, `Length(pdy^)` answers 1 and `High(pdy^)` answers 0 where FPC answers 5 and 4 — while `pdy^[1]` reads the right element. The pointee is a HANDLE, so the [data-8] header is one indirection further than the runtime path looks."
---

# Measured, 2026-08-25 (HEAD)

```pascal
type TDyn = array of LongWord; PDyn = ^TDyn;
var dy: TDyn; pdy: PDyn;
begin
  SetLength(dy, 5); dy[1] := 9; pdy := @dy;
  WriteLn(pdy^[1], ' ', Length(pdy^), ' ', High(pdy^));
end.
```

| | `pdy^[1]` | `Length(pdy^)` | `High(pdy^)` |
| --- | --- | --- | --- |
| fpc 3.2.2 | 9 | **5** | **4** |
| pxx | 9 | **1** | **0** |

(Before `bug-p-length-of-a-dereferenced-pointer-to-array-answers-zero` landed
this printed `38654705664` / `38654705663` — an address read as a length. It is
now a wrong small number instead of a wrong huge one; neither is right.)

# Cause

The fixed-array fix deliberately excludes `ArrTypeIsDyn` aliases: a dynamic
array's pointee is a HANDLE (pointer-sized), not the elements, so the extent is
not a compile-time constant and cannot be folded the way `array[0..3]`'s is.
What `Length(p^)` needs instead is to dereference ONE more level and then take
the ordinary `[data-8]` header — i.e. the runtime path over `p^` rather than
over `p`.

# Shape of the fix

Record on the pointer symbol that the pointee is a dyn-array alias (the
`ArrTypeIsDyn` branch the `^` arm currently skips), and route `Length`/`High` of
such a deref to the runtime `-tkLength` path with the deref node as the operand,
where today they take the whole-value fallback. `SetLength(p^, n)` should be
checked at the same time — it is the same indirection question.

# Gate

`make compiler/pascal26` + the repro diffed against fpc + `tools/gate.sh quick`.
`test/test_pointer_to_a_named_fixed_array.pas`'s header names this ticket where
the shape is deliberately not asserted.

## Log
- 2026-08-26 — resolved, commit cddf64977.

# Resolved 2026-08-26

The ticket's diagnosis was close but named the wrong mechanism, and the
difference mattered.

**It was not a missing case. It was a confident wrong answer built from two
fields nobody had written.** The ticket says the fixed-array fix "deliberately
excludes `ArrTypeIsDyn` aliases" — the exclusion exists at the alias parser
(`pasparser_decl.inc` ~229) but `LastTypePointerElemArrAi` is assigned
*unconditionally* right after it, so `AddSym` still ran the fixed-array branch
for a dyn pointee and computed `ArrTypeHi - ArrTypeLo + 1`. The dyn branch of
the alias parser never writes `ArrTypeLo/Hi`, so both were 0 — extent 1, low 0.
That is exactly the `Length = 1` / `High = 0` that was filed. So the first
change is a guard on `ArrTypeIsDyn`, and the number stops being invented.

**Then the real work: `p^` had to become a dyn-array VALUE.**
- `SymPtrElemDynDepth` (new) records the pointee's nesting on the pointer
  symbol — the slot that says "this deref is a dyn array" now that the extent
  slot correctly stays empty.
- `NodeDynDepth` / `NodeDynBaseTk` / `NodeDynBaseRec` grew `AN_DEREF` arms.
- The `tkLength` lowering's dyn arm was keyed on `not IsASTLValue`, and `p^`
  IS an lvalue, so it took the force-address path instead. Widened to admit an
  `AN_DEREF`, which routes it into the existing hidden-dyn-temp + `IR_LEA`
  machinery — the shape every backend's dyn-array Length path already serves.

## The measurement that saved it, and the bug it uncovered

Two plausible lowerings of the handle both **segfaulted**: lowering the deref
(`IRLowerAST(p^)`), and loading from the pointer's slot the way the
`Length(ps^)` managed-string arm does. A probe explained why, and the answer is
a separate, larger bug:

**`@dy` in pxx yields the HANDLE, not the address of the `dy` variable** —
unlike `@s` on a managed string, which was corrected to the slot address, and
unlike fpc, which gives the slot for both. So `p` already *is* the handle;
both attempts dereferenced it once too often. The lowering therefore takes `p`'s
value directly, with the measurement recorded at the site so the next reader
does not re-derive it.

That divergence is now filed as
[[bug-p-address-of-a-dynamic-array-captures-the-handle-not-the-variable]]. It
means a `^TDyn` goes stale across a reallocation — after `SetLength(dy, 9)` fpc
reads 9 and we read 5, off a buffer `SetLength` may already have freed. It was
unreachable until now precisely *because* `Length(p^)` answered a constant 1.

## Verified against fpc 3.2.2, byte-identical

`test/test_pointer_to_a_named_fixed_array.pas` covers a dyn pointee and a dyn
pointee with a **managed** element type. Both call `Length` through the pointer
200 times in a loop and then re-read the array: the hidden temp holds the handle
BORROWED, and if it ever owned it the first finalize would free the array and
every later read would be a use-after-free. Checked at 2000 iterations off-suite
too — no corruption, refcounts intact, `SetLength` afterwards still works.
The stale-after-realloc row is deliberately NOT asserted; it belongs to the
ticket above.
