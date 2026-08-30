---
slug: bug-p-generic-type-constraints-are-parsed-and-discarded
track: P
prio: 70
type: bug
blocked-by: []
status: done
created: 2026-08-30
summary: "`TFoo<T: class>` and every other generic constraint form is parsed and thrown away at pasparser_generic.inc:1321 (`Next; { skip the constraint list }`), so no specialization is ever checked against it. 35 of 35 FAIL-marked conformance tests that use ugenconstraints.pas are wrongly accepted on HEAD. NOT a regression -- constraint checking was never implemented; the six shard reds of 2026-08-30 09:10Z are d23f52948 removing the accidental barrier that was hiding it."
owner: frankR
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

---

## What landed (frankR, Track P)

Constraints are now **recorded** at template declaration and **checked** at each
specialization. `pasparser_generic.inc` only — no `defs.inc`, no
`pasparser_decl.inc`: the file already declares its own top-level globals
(`HoistName`, `SpecBoundNameOff`), so the storage went beside them and the
`symtab`/`defs` side is read-only.

**Measured, my own instrument, sha `f92f3c013ac5`:**

| | before | after |
| --- | --- | --- |
| 35 FAIL-marked tests using `ugenconstraints` | 0 rejected | **33 rejected** |
| `tgenconstraint1` (the only PASS test, ~35 valid specializations) | accepted | **accepted** |

The ticket's "35 of 35 wrongly accepted" reproduced exactly before the change
(`ok=1 mismatch=35`). After: `ok=34 mismatch=2`.

Every rejection names the **constraint**, which is the gate's actual condition:

```
tgenconstraint2:  TTest1<T> is constrained to `class`, but TTestRec is a value type
tgenconstraint23: TTest12<T> is constrained to `ITest1`, but TTestClass9 does not
                  implement or descend from it
```

Not one of them still dies on `ugenconstraints` failing to parse.

### The rule set the corpus actually pins

Reading the 36 tests as an oracle rather than implementing from the FPC docs
changed three things I would otherwise have got wrong:

1. **An interface constraint is satisfied by a class that DECLARES the
   interface, or by an interface that IS it or descends from it.** The second
   half is why `TTest5<IInterface>`/`<ITest1>`/`<ITest2>` are all valid against
   `T: IInterface` while `TTest7<IInterface>` against `T: ITest1` is not — the
   direction is the whole distinction.
2. **Declared, not inherited.** A class listing only `ITest2`
   (`= interface(ITest1)`) does **not** satisfy `T: ITest1`. Three FAIL-marked
   tests (18, 23, 25) pin this and all three pass under the naive reading.
3. **Ancestor CLASSES are walked** — `tgenconstraint1`'s `TTest15<TTestClass8>`
   is valid only because `TTestClass8` inherits `ITest1` from `TTestClass7`.

(2) was the awkward one: `pasparser_decl.inc` stores the interface CLOSURE, not
the declared list — it appends every ancestor interface so `is`/`as`/`Supports`
work. The declared set is recoverable without touching that file, because the
flattening *appends*: `implOrig` freezes the declared count first and IMT rows
keep `implIntf` order, so declared interfaces are a prefix and a row is
flattened-in exactly when an earlier row of the same class descends from it.

### Deliberately not done

- **`tgenconstraint4` (`LongInt`) and `5` (`TClass`) are still accepted** — the
  two remaining mismatches. Both name types that are not classes and never will
  be, but at check time "not a class" and "not declared yet" are the same
  observation, and rejecting on it rejects ordinary code. Measured, not
  hypothesised — an intermediate build that rejected on unresolved names broke
  both of these:

  ```pascal
  type TInner<T: class> = class end;
       TC = class end;          { declared before the use... }
       TA = TInner<TC>;         { ...and still unknown when the check runs }
  ```

  `DelphiRewriteGenericUses` inserts the alias declaration at `insertAt`,
  immediately after the TEMPLATE, so the specialization is parsed *ahead of*
  `TC`. The objfpc spelling has the same hazard via a forward `TC = class;`,
  whose stub carries no parent link. Both now take the conservative exit. The
  residual is a **missed rejection, never a wrong one**, which is the right way
  round — but it is also the sign that this check is in the wrong place.

- **`T: constructor` is enforced only as far as "must be a class."** The corpus
  pins exactly that much (4 tests, all passing a non-class); nothing anywhere
  requires a CLASS to be refused for lacking a parameterless constructor, so the
  other half would be an unverified rejection path over real code.

### The real fix for the residual, and why it is not here

Constraint checking is a **semantic** check and wants to run when the type
section closes, not mid-parse. The hook already exists and is already in this
file — `FlushPendingClassSpecializations` (`pasparser_generic.inc`), called from
`pasparser_decl.inc:6083` at `TypeSectionDepth = 0`. It is called only
`if PendingSpecCount > 0`, so a pending-constraint list cannot reach it without
making that call unconditional — one line, in **frankwasm's file**. Left for the
coordinator to sequence rather than taken unilaterally.

### Two findings for other lanes (not fixed here)

- **`tgenconstraint37` fails on `pinned` and on HEAD identically** — a forward
  `ITestInterface = interface;` is not parsed (`Expected: end, but got:`). Not
  constraint-related and not a regression; it is why that test cannot serve as
  the parse-order oracle it looks like.
- **`tools/gate.sh`'s forward-lint counts NESTED functions as globals.** It
  failed this work on `calls argName, declared at rparser.inc:504` — where
  `ArgName` is a nested function inside `RResultClassForRec`, invisible outside
  it, and mine was a *parameter*. Worked around by renaming the parameter;
  the lint is over-approximating. Track T/A.

## Log
- 2026-08-30 — resolved, commit f4fb9d31b.
