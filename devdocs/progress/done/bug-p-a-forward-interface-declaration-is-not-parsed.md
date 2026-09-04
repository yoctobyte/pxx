---
slug: bug-p-a-forward-interface-declaration-is-not-parsed
track: P
prio: 45
type: bug
blocked-by: []
status: done
created: 2026-08-30
summary: "`IFoo = interface;` (forward) is rejected with `Expected: end, but got: ;` while the CLASS arm of the same double case, `TBar = class;`, parses fine. Pre-existing on pinned and HEAD alike -- not a regression. Costs tgenconstraint37, which is otherwise the only corpus test that exercises specializing against a forward-declared type."
owner: frankB
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

## FIXED 2026-09-05 (frankB) — and the landmine was real, exactly as predicted

Two changes, and the second is the one the ticket warned would not be free.

**1. `compiler/pasparser_decl.inc`, the interface arm.** A `tkSemicolon` right
after the `interface` keyword mints the UCls row, marks `UClsForward`, and
stops — the same shape the class arm's `UClsForward[ci] := (not hadParens) and
(CurTok.Kind = tkSemicolon)` has always had. The full declaration then
**completes that row in place** rather than adding a second one, with the same
member-window re-anchoring and the same `UClsUnitIdx = CurrentUnitIdx` guard the
class arm carries, and for the reason its comment gives: `FindUClass` answers
with the first match, so a shadowing second row would take every later use with
it.

That distinction is why the test does not stop at "it compiled". Rows 1 and 2
call a method **through the interface** and through the class; a stub that was
shadowed rather than completed would compile the file and fail there.

**2. `compiler/pasparser_generic.inc`, `CheckTemplateConstraint`.** frankwasm's
prediction was exact: with the parse fixed, `specialize
TGenericIInterface<ITestInterface>` was refused —

```
generic constraint violated: TGenericIInterface<T> is constrained to
`IInterface`, but ITestInterface does not implement or descend from it
```

`T: IInterface` is the **exact mirror of `T: TObject`**, which had the same bug
for the same reason and whose fix is already sitting in the else-branch
alongside. An interface's `UClsParent` is -1 unless it names a parent
explicitly, so `GCIntfDescends` walks a chain that structurally never reaches
`IInterface` and answered True only when `argCi = conCi`. A forward stub has no
chain at all, which is why nothing reached it until forward declarations started
parsing. Answered in the coordinate system where it is expressible: in Pascal
every interface descends from `IInterface`.

**Not a loosening, and the three negative controls say so.** All still refuse,
and fpc 3.2.2 refuses all three too (different wording — deferred):

| probe | result |
| --- | --- |
| `TT<IInterface>` against `T: ITest1` (ancestor, not descendant — tgenconstraint17) | refused |
| a forward CLASS stub against `T: IInterface` | refused ("the stub implements nothing yet") |
| a record against `T: IInterface` | refused |

The direction still goes through `GCIntfDescends` unchanged; only the root
constraint short-circuits.

## The corpus row cannot be checked from here

`library_candidates/` in this checkout holds busybox, html5lib, reportlab,
rtl-generics, tinycss2 and webencodings — **there is no fpc-testsuite tree**, so
`tgenconstraint37.pp` could not be run to confirm it turns green. What is
measured is its SHAPE, reproduced from the excerpt in this ticket: two forward
declarations, one class and one interface, specialized against `T: TObject` and
`T: IInterface` before either is completed. That compiles and runs here and
under fpc. Whoever has the corpus should confirm the row itself; the claim in
this ticket's body that it fails "on this alone" is now the only untested link.

## Gate

`make compiler/pascal26` converged; `tools/gate.sh quick` GREEN with the FPC seed
canary CONCURRENT. `test/test_forward_interface_decl.pas` matches fpc 3.2.2
row for row and the pin refuses it at its first type line;
`test/test_forward_interface_constraint_fail.pas` is the negative half, in its
own file because a refusal cannot share a program with rows that must compile.


## Log
- 2026-09-05 — resolved; this names the commit that carried the resolve, which is not always the one that carried the change — commit d750d86a4.
