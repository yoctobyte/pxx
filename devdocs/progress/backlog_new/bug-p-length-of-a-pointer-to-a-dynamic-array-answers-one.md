---
slug: bug-p-length-of-a-pointer-to-a-dynamic-array-answers-one
title: "`Length(p^)` over a pointer to a named DYNAMIC array answers 1, and `High(p^)` answers 0"
track: P
prio: 30
type: bug
blocked-by: []
status: backlog_new
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
