---
track: P
prio: 40
type: bug
blocked-by: []
status: done
owner: frankS
---

# An imported generic routine is spliced before the program's own type section

A `generic function` declared in a UNIT and specialized on a type declared in
the importing PROGRAM does not compile: the specialized body is spliced at the
end of the program's `uses` clause, which is ahead of every type the program
itself declares, so the substituted type argument is not in scope yet.

`tgenfunc19.pp:32` is the corpus row. The program declares `TTest2`, calls
`specialize DoTest<TTest2>`, and the spliced `Result := TTest2.Test` is refused
with `undefined variable (TTest2)` — a scope diagnostic pointing into
`ugenfunc19.pp`, because the template text came from the unit.

**CONTROL, measured at compiler `1764cc174080`, not reasoned about.** The same
program with the type argument declared IN THE UNIT compiles and prints the
right answer (9):

```pascal
unit uA;   { TBase, TInUnit, generic function DoTest<T: TBase> }
program pA;  uses uA;  begin WriteLn(specialize DoTest<TInUnit>); end.
```

So the substitution machinery, the arity check and the call-site rewrite are all
correct. **It is the splice POSITION alone** — the one variable that differs
between the two programs is where the argument type is declared relative to the
uses clause.

## Why the splice is there, and why moving it is not a one-liner

`SpecializeImportedGenericFuncUses` runs at the end of `ParseUsesClause` for a
reason its own comment states at length: ahead of `TokPos` is the only safe
direction to edit in, because `RemoveTokens` shifts token indices and
`AdjustPass2Spans` is a no-op outside the body pass, so a removal BEHIND
`TokPos` invalidates `TokPos` and every `DeclItem` span already recorded. The
uses clause is the earliest point at which "every template this clause imported
is registered, and every use lies ahead" is true.

That argument is about the **rewrite** of the use sites (`specialize F<C>` ->
`F_C`), which genuinely must happen ahead of `TokPos`. It is not an argument
about where the **body** is spliced. The likely shape of the fix is to split the
two: rewrite the call sites at the uses clause as today, and defer the
`SpecializeStream` + `ParseSubroutine` of the specialized body until a point
after the program's declarations — the same relative position a locally
declared template already gets, which is why the local case has never had this
bug.

Not attempted here: it moves a splice site that four call paths share
(`ParseGenericFunctionDef`, `ParseTopLevelSpecialize`,
`SpecializeImportedGenericFuncUses`, `ExpandGenericMethod`), and the local and
imported cases would stop sharing one routine. Worth doing as a piece of work,
not on the way past.

## Related

The FIRST wall on this row was a different defect and is fixed: the call-site
predicate required a trailing `(`, so `specialize DoTest<TTest>` — a
parameterless call, which Pascal spells without parentheses — was declined and
left in the stream to be read as an expression (`undefined variable
(specialize)`). Fixture:
`test/test_a_parameterless_generic_routine_is_called_without_parentheses.pas`.
That fix also burned `tgenfunc12.pp`, whose skip reason named the same missing
spelling.

## FIXED 2026-09-08 at compiler `d1d78434de8c` — and the LOCAL case had it too

The concrete body is no longer spliced at the template's own position.
`SpecializeInlineGenericFuncUses` QUEUES it (`PendFunc*`, the routine-side twin
of `PendingSpec*`) and `FlushPendingFuncSpecializations` empties the queue where
the declaration section ENDS — `ParseProgram` just before `afterDeclTok`,
`ParseUnit` just before `afterImpTok`. That is the first token at which every
top-level type of the compilation unit is declared, which is the only thing the
concrete body needed.

Splicing there moves no recorded index: every `DeclItem` span was recorded
BEHIND that token and `Pass2Active` is still False, so the hazard
`AdjustPass2Spans` exists for is not live yet.

### THIS TICKET'S "the local case has never had this bug" IS FALSE, AND IT IS THE FINDING

Measured at `cd2d264c72df`, one file, no unit, no import:

```pascal
program g2;
generic function DoIt<T>(a: T): LongInt;
begin Result := a.Test; end;
type TA = record Test: LongInt; end;      { declared AFTER the template }
...  WriteLn(specialize DoIt<TA>(x));     { pxx: unknown type: TA   fpc: 9 }
```

Move the `type` above the `generic function` and it compiles. **The local case
worked only when the type happened to precede the template**, which is the
ordinary way anyone writes it — so the constraint was invisible and the defect
read as an import problem. It is one defect with three faces: an imported
template over a program type, a local template above its type, and a
routine-local type argument, which is never in scope at top level at all.

That also retires this ticket's proposed target — *"the same relative position a
locally declared template already gets"*. That position is the bug.

### tgenfunc19.pp DOES NOT BURN, AND ITS SKIP REASON IS NOW WRONG IN THE OTHER DIRECTION

The file compiles and links now. It still exits `rc=1`, on a SECOND wall the
splice defect was hiding:

```
DoTest<TTest>  = 1   fpc 2      <- the unit's class HELPER is not applied
DoTest<TTest2> = 3   fpc 3      <- correct
```

**Pre-existing, proved by stash-and-rebuild**: `cd2d264c72df`, without this
change, answers 1 for the same call. So the skip reason's *"the reason here
named a CLASS-HELPER rule that was already carved out … and was never this row's
wall"* was TRUE about the wall it was measuring and is FALSE as a claim about
the file: the helper rule was the NEXT wall, standing behind the one being
described. Filed as
[[bug-p-a-generic-routine-body-does-not-see-its-own-units-class-helper]]; the
row's reason is rewritten to name it.

`DoTest<TTest2>` answering 3 rather than the program helper's 4 is the harder
half and it is already correct — the body resolves `T.Test` against the class,
not against a helper declared in the specializing program.

### Fixture

`test/test_a_specialized_routine_body_lands_after_the_declarations.pas`
(`test_gfsplice26`) with `test/units/ugenfuncsplice.pas`, differential against
fpc 3.2.2, four rows — and two of them are the controls that hid this:
`local-below` and `unit-unittype` are the shapes that always worked, so the file
prints which of the four spellings a future regression breaks. Each row returns
a different tag (11, 22, 33, 44), so no row can pass by picking up another row's
specialization, and none of those is a zero, a default or `SizeOf(Integer)`.
Positive control on pin v407: `unknown type: TInProg`, reported against the
UNIT's file, which is the reported diagnostic's own shape.

## Log
- 2026-09-08 — resolved; this names the commit that carried the resolve, which is not always the one that carried the change — commit PENDING-COMMIT.
