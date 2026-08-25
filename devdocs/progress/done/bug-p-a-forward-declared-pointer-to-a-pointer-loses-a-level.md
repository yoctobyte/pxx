---
slug: bug-p-a-forward-declared-pointer-to-a-pointer-loses-a-level
title: "`PPInt = ^PInt;` written above `PInt = ^Integer;` makes the second `^` illegal"
track: P
prio: 50
type: bug
blocked-by: []
status: done
owner: claude-A
created: 2026-08-25
summary: "A pointer alias whose pointee is another pointer alias declared LATER kept depth 1, so `pp^^` was refused with `dereferenced value is not a pointer`. Swapping the two type declarations made the identical program compile and run. The forward fixup pass had an arm for this and it could never fire — it required the element to ALREADY be tyPointer, which a forward reference can never be. FIXED this session."
---

# Measured, 2026-08-25

```pascal
type
  PPInt = ^PInt;      { forward: PInt does not exist yet }
  PInt  = ^Integer;
var v: Integer; p: PInt; pp: PPInt;
begin
  v := 42; p := @v; pp := @p;
  WriteLn(p^);      { 42 }
  WriteLn(pp^^);    { pascal26: dereferenced value is not a pointer }
end.
```

Reverse the two type declarations and the same program compiles and prints
`42 42`. **A declaration order deciding whether a program parses is the tell** —
and the forward order is the one real code uses, because it is the only one that
works for mutually referential types.

# Root cause

`ParseTypeKind`'s forward escape hatch answers `tyInteger` for a name it cannot
see yet (`PtrElemDepth > 0`), which is right for `PNode = ^TNode` and leaves the
row to be repaired by `ResolvePendingPointerAliases`. That pass had an arm for a
pointee that is itself a pointer alias:

```pascal
if (targetAlias >= 0) and (AliasTk[targetAlias] = Ord(tyPointer)) and
   (AliasPtrDepth[targetAlias] > 0) and (AliasElemTk[i] = Ord(tyPointer)) then
```

The last conjunct is unsatisfiable for the case the arm exists to serve: a
forward reference cannot have recorded `tyPointer`, because that is precisely
what it did not know. So the arm only ever repaired the BASE of a row that was
already correct, and never repaired a row that needed it — and it repaired the
base while leaving `AliasPtrDepth` at 1, which reads as "one `^` and you are at
the base", so the second `^` was refused.

# Fix (landed 2026-08-25)

Drop the unsatisfiable conjunct and take the whole triple from the target: the
element becomes `tyPointer`, the depth becomes the pointee's depth plus one, and
the base is the pointee's base. `AliasElemRec` deliberately stays `REC_NONE` —
the immediate pointee is a POINTER, which has no record of its own; the record
that matters lives in `AliasPtrBaseRec`, where every reader of a multi-level
pointer looks.

Regression test `test/test_pointer_to_a_pointer_through_a_cast_and_a_forward.pas`
asserts both declaration ORDERS, so the fix cannot rot back into the
order-dependent state.

# Where it was found

[[feature-pascal-corpus-generics]] — rtl-generics declares
`PPExtendedEqualityComparerVMT = ^PExtendedEqualityComparerVMT` in exactly this
forward order.

## Log
- 2026-08-25 — resolved, commit 15ec54d7a.
