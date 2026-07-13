---
prio: 40
---

# Operator overload not found when a record operand is a CALL RESULT

- **Type:** bug (compat — hard error, easy workaround)
- **Track:** P — Pascal frontend (shared `parser.inc`, so Track A file-lane)
- **Status:** done

## Symptom
```pascal
d := TPt.Create(1, 2) + TPt.Create(10, 20);
{ error: no operator overload found for record operands }
```
The same operator resolves fine when the operands are variables:
```pascal
b := TPt.Create(1, 2);
c := TPt.Create(10, 20);
d := b + c;               { works }
```

## Cause
Operator dispatch for record operands identifies the operand's record type from an
lvalue/ident shape. A record-valued CALL node (an advanced-record constructor, or any
function returning a record) is not recognised, so the lookup never finds the overload — it
reports "not declared" for an operator that IS declared, which is the misleading part.

## Workaround
Bind the call result to a variable first. One line.

## Fix
Resolve the operand's record id from the NODE's type (`ResolveNodeRec` / `ASTTk` +
`LastTypeRecId`) rather than from an lvalue shape, so any record-valued expression qualifies.
Worth checking the same lookup for record-valued function results generally, not just ctors —
they are the same shape.

## Gate
`make test` + self-host byte-identical.

## Log
- 2026-07-13 — found while landing advanced-record `class operator`
  ([[feature-pascal-record-constructors]]). Split out rather than widening that change.

## RESOLVED 2026-07-14 (b333)
ResolveNodeRec's AN_CALL case falls back to the LIFTED TEMP's RecName when the
proc carries no return rec — a record CONSTRUCTOR "returns" through the hidden
temp, so operator dispatch (and everything else asking "which record is this
call?") now sees it. Bonus in the same commit: postfix selectors chain on the
factory result (TPt.Create(7,8).Sum), closing the other gap noted on
feature-pascal-record-constructors. Pinned: test_record_ctor_expr_tails_b333.
- 2026-07-14 — resolved, commit HEAD.
