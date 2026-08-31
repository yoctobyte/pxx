---
slug: bug-p-a-forward-interface-declaration-is-not-parsed
track: P
prio: 45
type: bug
blocked-by: []
status: open
created: 2026-08-30
summary: "`IFoo = interface;` (forward) is rejected with `Expected: end, but got: ;` while the CLASS arm of the same double case, `TBar = class;`, parses fine. Pre-existing on pinned and HEAD alike -- not a regression. Costs tgenconstraint37, which is otherwise the only corpus test that exercises specializing against a forward-declared type."
---

# P: a forward `interface` declaration is not parsed

## Repro — six lines, and its own control

```pascal
program fi1;
{$mode objfpc}
type
  IFoo = interface;      { forward }
  IFoo = interface
  end;
begin
end.
```

```
pascal26:4: error: unexpected token
  Expected: end, but got:  (Kind: 78, Line: 4)
  near: fi1  type IFoo  interface >>>  IFoo
```

The control is the same declaration one keyword over, and it works:

```pascal
  TBar = class;          { forward -- accepted }
  TBar = class
  end;
```

**This is a double case with one arm missing** — the shape
`devdocs/dev/normalise-dont-special-case.md` is about. `pasparser_decl.inc`
already detects a bodyless class (`UClsForward[ci] := (not hadParens) and
(CurTok.Kind = tkSemicolon)`) and the interface arm never got the same test, so
the parser walks into the body it assumes is there and asks for the `end` that
is not coming.

## Not a regression

Identical failure on `pinned` and on HEAD, with only the wording differing
(`pinned` says `expected 'end' before ';'`). Nothing recent broke it; it was
never implemented.

## Why it is worth more than its size

`library_candidates/fpc-testsuite/tests/test/tgenconstraint37.pp` is
`%NORUN`-marked (should compile) and fails on this alone. That test is the
**only** one in the tgenconstraint set that specializes a generic against
forward-declared types:

```pascal
  TTestObject = class;
  ITestInterface = interface;

  TGenericTObjectTTestObject = specialize TGenericTObject<TTestObject>;
  TGenericIInterfaceITestInterface = specialize TGenericIInterface<ITestInterface>;

  TTestObject = class end;
  ITestInterface = interface end;
```

which makes it the natural oracle for exactly the parse-order hazard
[[bug-p-generic-constraints-are-checked-before-the-type-section-closes]] is
about — constraints checked before the argument's real declaration is reached.
It cannot serve as that oracle while it dies at line 18 for an unrelated reason.
Fixing this turns one FAIL green AND unblocks the test that would prove the
other ticket's fix.

Found while resolving
[[bug-p-generic-type-constraints-are-parsed-and-discarded]]; checked against
`pinned` before shipping precisely so it would not be mistaken for fallout of
that work.

## A second consumer, and a landmine inside it (frankwasm, 2026-08-31)

This gap is what holds `tgenconstraint37` at rejected-valid — the only remaining
disagreement in the 40-file `tgenconstraint*.pp` corpus, now 39/40 after
[[bug-p-generic-constraints-are-checked-before-the-type-section-closes]]. So
closing this ticket is worth one corpus row beyond its own repro.

**Do not expect it to be free.** 37 declares `ITestInterface = interface;` and
then specializes `TGenericIInterface<ITestInterface>` — an interface forward stub
against `T: IInterface` — and fpc accepts it (`%NORUN`). As of 2026-08-31 the
constraint checker JUDGES forward stubs rather than skipping them: a class stub
is treated as a class whose ancestry is TObject and which implements nothing yet,
which is what fpc does. The interface mirror of that rule — an interface stub
descends from `IInterface` — is **not written**, because nothing can currently
reach it. `GCIntfDescends` walks a parent chain the stub does not have yet, so
the moment the parse succeeds that line will likely be refused.

The fix, if it is needed, is the same shape as the class one already in
`CheckTemplateConstraint`: `T: TObject` is answered as `isClass` rather than by
walking parents, because every class descends from TObject. Every interface
descends from IInterface the same way.
