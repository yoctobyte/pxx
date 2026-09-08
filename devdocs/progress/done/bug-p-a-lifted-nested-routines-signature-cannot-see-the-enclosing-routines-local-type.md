---
track: P
prio: 55
type: bug
blocked-by: []
status: done
owner: frankS
---

# A lifted nested routine's SIGNATURE cannot see the enclosing routine's local type

`unknown type: TR` for a name that resolved correctly one pass earlier, reported
inside `builtinheap.pas` — a unit the programmer never wrote.

```pascal
procedure A;
type TR = record F: LongInt; end;
  function Get(const x: TR): LongInt;      { pxx: unknown type: TR }
  begin Get := x.F; end;
begin ... end;
```

fpc compiles it and prints the value. The BODY was never affected — `var r: TR;`
inside the same nested routine works — which is why every earlier probe of
routine-local scoping passed over this.

## Cause

Nested routines are lambda-lifted: `FlushPendingNestedProcs` re-injects the
stashed tokens as a fresh top-level `DeclItem`, and pass 2 parses that item as an
ordinary sibling. `ParseSubroutine` must read the parameter and result types
BEFORE it can identify the routine (the signature is what overload resolution
keys on), and at that moment `CurProc` is -1. `ScopeReachesProc` walks
`ProcLexParent` outward **from `CurProc`**, so with no routine in force the
enclosing routine's `AliasOwnerProc`/`UClsOwnerProc` row is unreachable and the
name resolves to nothing. Once the body starts, `CurProc` is the lifted routine
whose `ProcLexParent` already points at the enclosing one — hence the body/header
split.

**It is a regression from `0221a024a`** ("routine-local declarations are scoped
in all five name tables, not one"), and the `done/` ticket that change closed
predicted this door and looked at the wrong one: it rejected *"truncate
AliasCount at routine end"* precisely because *"FlushPendingNestedProcs appends
the inner routine as a FRESH DeclItem parsed after the enclosing body finishes,
so its legitimate references to the outer routine's types would be gone"* — the
hazard was named, and the scope-key fix reached it anyway through the header
rather than through a truncation. Measured against the pinned compiler, which
predates the scope key: rows 1, 2, 4 and 5 of the fixture COMPILE there, because
without any scope key the lookup falls through to the first global-ranked row and
is accidentally right whenever the spelling is declared once.

## Fix

`ScopeStartProc` (symtab.inc), used by both `ScopeReachesProc` and
`ScopeHopsToProc`: `CurProc` when a body is in force, else `LiftedScopeProc` —
set from a new `DeclItemOwnerProc` column that `FlushPendingNestedProcs` fills
from `PendNestRtnParent`, recorded at stash time when the enclosing routine is
still `CurProc`. Cleared to -1 immediately after each item, and initialised to -1
explicitly rather than left to BSS, since 0 is a real proc index.

## The row that cannot pass by accident

`test/test_a_lifted_nested_routines_signature_sees_the_enclosing_local_type.pas`,
six rows against the fpc 3.2.2 oracle. Rows shadow-a/shadow-b declare DIFFERENT
records under one spelling in two sibling routines, so a "fix" that made the
header resolve globally rather than in the writing routine's scope gives both
nested routines the same record and fails — which is exactly what the pinned
compiler does (`"S": no such member on this record/class`).
