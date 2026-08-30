---
slug: bug-p-generic-type-constraints-are-parsed-and-discarded
track: P
prio: 70
type: bug
blocked-by: []
status: open
created: 2026-08-30
summary: "`TFoo<T: class>` and every other generic constraint form is parsed and thrown away at pasparser_generic.inc:1321 (`Next; { skip the constraint list }`), so no specialization is ever checked against it. 35 of 35 FAIL-marked conformance tests that use ugenconstraints.pas are wrongly accepted on HEAD. NOT a regression -- constraint checking was never implemented; the six shard reds of 2026-08-30 09:10Z are d23f52948 removing the accidental barrier that was hiding it."
---

# P: generic type constraints are parsed and discarded — nothing is ever checked

## Root cause, one line

`compiler/pasparser_generic.inc:1321`, in the type-parameter loop:

```pascal
if Eat(tkColon) then
  while (CurTok.Kind <> tkSemicolon) and (CurTok.Kind <> tkGt) and
        (CurTok.Kind <> tkEOF) do
    Next;   { skip the constraint list }
```

The constraint is consumed to keep the parse moving and **never recorded**, so
there is nothing for a specialization to be checked against. `T: class`,
`T: record`, `T: constructor`, `T: <some class>` and `T: <some interface>` are
all accepted and all mean nothing.

## Measured

`library_candidates/fpc-testsuite/tests/test`, HEAD vs `pinned`:

| | pinned | HEAD |
| --- | --- | --- |
| `tgenconstraint{6,10,16,21,27,32}.pp` — all FAIL-marked | rejected | **accepted** |
| all 35 FAIL-marked tests that `uses ugenconstraints` | rejected | **35/35 accepted** |

So the reported six is a **shard artifact, not the blast radius.** The full-tier
red count 4 -> 10 undercounts by design; the honest figure is 35.

## Why it surfaced on 2026-08-30 and what that does NOT mean

`d23f52948` ([[bug-p-object-value-types-standard-meaning]]) landed ~08:50Z; the
09:10Z tier went red. Causation is established, and it is not the story it looks
like.

`pinned` rejected all six for a reason that has nothing to do with constraints:

```
pascal26:67: error: unexpected token in a unit interface section: it starts no
                    declaration (a mistyped section header?)
  in: ugenconstraints.pas
  near:  end  TTestObject1  object >>> end  type
```

`ugenconstraints.pas:65` declares `TTestObject1 = object`. **The shared unit did
not parse**, so every test that uses it failed to compile, and 35 FAIL-marked
tests were green because of a syntax error in a file none of them were testing.
Giving `object` its standard meaning made the unit parse, which removed the
barrier and exposed that the checks behind it were never there.

**This is the second instance of the same shape today** — an earlier syntax wall
masking what is behind it, the other being `generics.collections.pas` :146
hiding :120 ([[bug-p-generic-type-param-unresolved-in-class-abstract-template]]).
Worth stating as a pattern for whoever reads corpus results: **a conformance
test that passes because the file it depends on will not compile is not passing,
and nothing in the output distinguishes the two.**

## Not a revert candidate, and this is the load-bearing judgement

Reverting `d23f52948` would restore green on all 35 — by restoring a false
green, and by re-breaking real Pascal source (`generics.collections`). The reds
are **honest**: they are the first accurate report this suite has given about
constraint checking. The correct action is to implement the checks, not to
re-hide them.

Two of the six also cut against the object link on their face —
`tgenconstraint21` (`TTest8<ITest1>`) and `27` (`TTest15<TTestClass4>`) name no
`object` at all — and the measurement explains that too: they never reached
their own constraint, because the unit they import died at line 65. The
coordinator flagged both as disconfirming and was right to; they are explained
rather than dismissed.

## Classification

**Bug, not the compat table's laxness row.** CLAUDE.md says *"we accept a form
FPC rejects -> not a defect"*, and read flatly that covers `accepted-invalid`.
It does not apply: that row is about **deliberate** dialect choices, and this is
a check that was never written. A constraint the author wrote and the compiler
silently ignores is the silent-wrong-behaviour escape — the program compiles and
the guarantee that was asked for is absent.

## Scope

The five constraint forms in `ugenconstraints.pas`, in rough order of how much
real code uses them:

1. `T: class` — must be a class type;
2. `T: record` — must be a value type;
3. `T: <ClassName>` — must be that class or a descendant;
4. `T: <IInterfaceName>` — must implement it;
5. `T: constructor` — must have a parameterless constructor.

Constraints can be **combined** (`T: class, IInterface, constructor`) and there
is one per type parameter, so the storage is a per-parameter list, not a scalar.

Do not aim at all five at once. Recording the constraint at all is the change
that matters; the first form to enforce is whichever the corpus actually uses
most, and the count is in that directory.

## Consequences

Closes and replaces the six auto-filed shard tickets of 2026-08-30, which are
six views of this one defect:
`regression-test-pascal-conformance-shard{0-6-3,1-6,2-6,3-6,4-6-3,5-6-3}`.
They were correctly re-laned from T to P by the coordinator — generic constraint
checking is frontend semantics, and the runner names no lane.

## Gate

`make compiler/pascal26` + the 35 FAIL-marked tests using `ugenconstraints`
rejected again — **for their own reason this time**, which whoever fixes this
must verify by checking the diagnostic names the constraint rather than the
unit. Breadth is Track T's against the pushed sha.
