---
track: P
prio: 35
type: bug
summary: "`SizeOf(p^.A)` is a parse error (`Expected: ), but got: ^`). SizeOf's operand parser is a hand-rolled selector walk that handles `v`, `v.f.g` and `v[i]` but has no `^` case, so any pointer deref in the operand is rejected outright."
---

# `SizeOf` rejects a pointer deref in its operand

- **Type:** bug (Pascal frontend) — **Track P**
- **Filed:** 2026-08-20 (frank1-ACP), while fixing
  [[bug-p-sizeof-an-array-field-returns-the-element-size]].
- **Shared-file catch:** the fix lands in the SHARED `compiler/parser.inc`.
  Whoever takes it obeys Track A's gate and the no-concurrent-edit rule.

## Repro

```pascal
type TR = record A: array[0..2] of Integer; end;
     PR = ^TR;
var r: TR; p: PR;
begin
  p := @r;
  WriteLn(SizeOf(p^.A));    { pxx: Expected: ), but got: ^   FPC 3.2.2: 12 }
end.
```

`SizeOf(r.A)` and `SizeOf(p^)` are fine; it is the deref *inside* a selector
chain that has no case.

## Why it is filed separately, and low

It is a **loud** failure — a parse error at the exact token, not a wrong value —
which is the opposite of its parent ticket's failure mode, and nothing silently
miscomputes. It is filed at 35 rather than folded into that fix because the cheap
version means adding a fourth shape to `SizeOf`'s hand-rolled operand walk, which
is the structure that produced the parent bug in the first place.

## The shape worth considering first

`SizeOf`'s operand parser is a private re-implementation of the selector chain:
separate branches for a bare var, `v.f.g`, `v[i]` on a 1-D array, and `v[i,j]` on
an N-D one, none of which know about `^`, and each carrying its own size formula.
The parent ticket already collapsed the field formula into `RecFieldByteSize`.
The real fix is probably to stop hand-rolling: parse the operand with the ORDINARY
lvalue parser (which handles `^`, indexing, chains and casts already) in a
non-evaluating mode, and ask the resulting node for its type + extent. That is a
bigger change than this symptom justifies on its own, which is why this sits in
backlog rather than being squeezed in — but it is the version that would also
retire the `wrong number of array subscripts` and `SizeOf: unknown field` special
cases. See `devdocs/dev/root-cause-over-microfix.md`.
