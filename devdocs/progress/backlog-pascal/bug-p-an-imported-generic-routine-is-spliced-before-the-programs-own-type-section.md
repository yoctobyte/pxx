---
track: P
prio: 40
type: bug
blocked-by: []
status: open
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
