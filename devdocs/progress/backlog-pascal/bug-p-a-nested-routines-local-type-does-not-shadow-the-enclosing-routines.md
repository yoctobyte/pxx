---
track: P
prio: 50
type: bug
blocked-by: []
status: open
owner: frankS
---

# A nested routine's local type does not shadow the enclosing routine's

Silent wrong value, no diagnostic, no generics required. The inner `TRec` is
ignored and every use in the nested routine binds the OUTER one.

```pascal
procedure Outer;
type TRec = packed record p, q, r: Byte; end;      { 3 }
  procedure Inner;
  type TRec = packed record s: Byte; end;          { 1 }
  begin Writeln(SizeOf(TRec)); end;                { pxx 3, fpc 1 }
begin Inner; end;
```

## Cause: the alias table has no routine scope

`FindTypeAlias` (symtab.inc) ranks on two keys only — `AliasOwnerCi` (the CLASS
body a row was declared in) and `UsesRankOf` — and **ties keep the FIRST row**.
Routine-local types are appended with `AliasOwnerCi = -1` like any unit-level
type, so the enclosing routine's row is simply the earlier one and wins. There
is no `AliasCount` save/restore anywhere for Pascal: the rows are never popped.

Why the leak nobody has hit is hidden: `var w: TLocalOnly;` at program level
after a routine correctly says `unknown type`, but not because of scoping — the
routine's local `type` section is parsed in PASS 2, after the program's var
section has already been read. The scope rule is absent; the pass order is
standing in for it.

## Both one-line fixes are wrong, which is why this is a ticket

- **Truncate `AliasCount` at routine end.** Breaks lifted nested routines:
  `FlushPendingNestedProcs` appends the inner routine as a FRESH DeclItem parsed
  after the enclosing body finishes, so its legitimate references to the outer
  routine's types would be gone.
- **Prefer the LAST matching row instead of the first.** Fixes shadowing while
  the inner routine is being parsed and breaks visibility after it: the inner
  row outlives the routine and would then shadow a unit-level type of the same
  name for the rest of the compilation.

The fix is a real scope key on the alias row (the proc it was declared in, plus
enclosing-proc reachability), not a rank tweak.

## What is green over it, and cannot see it

`tgeneric94.pp` passes today. It compares `SizeOf(t.f)` against
`TRecSize_Nested = SizeOf(TRec)` — **both sides resolve through the same broken
lookup**, so they agree while both are wrong, and the row would pass if this
machinery did nothing at all. Its skip row was burned on the strength of the
`bug-p-a-specialization-in-a-routine-local-type-section-desyncs-the-parse` fix,
which is a true statement about that defect and not about this one.

`test/test_routine_local_specialization.pas` deliberately names the inner and
outer types APART so its red would be about the splice; the repro above is the
only assertion that fails on this.
