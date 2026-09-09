---
track: P
prio: 45
type: bug
blocked-by: []
status: done
owner: frankZ
created: 2026-09-08
summary: "FIXED 2026-09-09. A class helper's CLASS-LEVEL members were never applied: `TTest.CS` answered the class's own 1 against fpc's 2, non-static `CN` 10 against 20, while INSTANCE members dispatched correctly (400 in both). Not generics and not `static` -- the discriminator was the RECEIVER, a class-level member reached through `TClass.Method`. ONE QUESTION, FOUR COPIES: ClassHelperRecFor's own comment said there were TWO member-lookup loops and there were four. The two INSTANCE loops asked it unconditionally; the metaclass arm (pasparser_lval.inc:1486) asked it only as a FALLBACK, so a helper could ADD a class method and never OVERRIDE one; ParseFactorCore's type-name arm never asked at all. All four now ask, and ask FIRST -- free, because it returns its input unchanged when the class's own member wins. THE TWO CLASS-LEVEL ARMS ARE SEPARATELY REACHABLE and a test of expressions alone certifies half a fix: with only the ParseFactorCore arm fixed, seven rows were correct and `TTest.Touch;` in STATEMENT position still answered 1. Eight rows asserted, seven matching fpc 3.2.2 exactly. THE EIGHTH DIVERGES ON PURPOSE: `gen-TTest2` is now 4 against fpc's 3 -- the second defect, revealed and not caused, pinned at 3 in 17a0e4bd6 before dispatch was touched exactly as frankS asked. (17a0e4bd6's message and this ticket's 09-09 note both claimed frankS's instance row was a weaker measurement than mine; that was MY error -- their probe numbers the helper at 200 where mine numbers it 400, so the two readings are identical. Corrected in the body; the commit message cannot be.) Split out as bug-p-a-generic-template-body-is-resolved-in-the-specializers-scope-not-its-own; do NOT chase it by narrowing dispatch, the other seven rows are the constraint."
---

# The shape

`library_candidates/fpc-testsuite/tests/test/ugenfunc19.pp`, unmodified:

```pascal
unit ugenfunc19;
type
  TTest = class class function Test: LongInt; static; end;
  TTestHelper = class helper for TTest class function Test: LongInt; static; end;
generic function DoTest<T: TTest>: LongInt;
implementation
class function TTest.Test: LongInt;       begin Result := 1; end;
class function TTestHelper.Test: LongInt; begin Result := 2; end;
generic function DoTest<T>; begin Result := T.Test; end;
end.
```

```
pxx   DoTest<TTest> = 1
fpc   DoTest<TTest> = 2
```

Both the class and its helper are declared in the template's OWN unit, above
the template. Nothing about the specializing program is involved in this row.

## Two rows, and they pull in opposite directions

Measured at `d1d78434de8c` with the program from `tgenfunc19.pp`:

| call | pxx | fpc 3.2.2 |
| --- | --- | --- |
| `specialize DoTest<TTest>` — helper in the TEMPLATE's unit | **1** | 2 |
| `specialize DoTest<TTest2>` — helper in the SPECIALIZING program | 3 | 3 |

**The second row is already right and is the constraint on any fix.** FPC binds
the body's names in the template's declaration context, so a `class helper`
written by the specializing program does not reach it. Widening helper lookup at
the specialization site would fix row 1 and break row 2 — and row 2 breaking is
the silent direction, since 4 is as plausible a number as 3.

So the question is not "are helpers applied" but "**which scope's** helpers", and
the answer is the template's unit, not the specialization's.

## Why it was invisible until today

The splice-position defect
(`bug-p-an-imported-generic-routine-is-spliced-before-the-programs-own-type-section`)
refused this file at `unknown type: TTest2` before any of it ran. That ticket's
skip reason for `tgenfunc19.pp` says the class-helper rule *"was already carved
out … and was never this row's wall"* — true about the wall being measured then,
and false as a claim about the file. **A wall behind a wall reads as no wall.**

## Corpus

`tgenfunc19.pp`, and it is now the file's ONLY remaining wall: it compiles,
links, and exits `rc=1` at `if specialize DoTest<TTest> <> 2 then Halt(1)`.


## 2026-09-09 (frankS) — measured, and the premise above is false

frankZ proposed splitting this between helper dispatch and generics scope and
asked whether the framing held. It does not, and the measurement is cheap enough
that it should have been made before the ticket was written — mine was.

Adding a plain non-generic `TTest.Test` **inside ugenfunc19 itself**, alongside
the corpus rows, at compiler `0f14028acc04`:

| row | pxx | fpc |
| --- | ---: | ---: |
| `specialize DoTest<TTest>` | 1 | 2 |
| `specialize DoTest<TTest2>` | 3 | 3 |
| **`InUnitPlain` — plain `TTest.Test`, inside the unit** | **1** | **2** |
| `TTest.Test` from the program | 1 | 2 |
| `TTest2.Test` from the program | 3 | 4 |

Rows 3–5 contain no generics. The substituted body behaves exactly like
hand-written code, which is the one thing the old body said it did not do.

### The boundary — one class, one helper, three member shapes

| shape | pxx | fpc |
| --- | ---: | ---: |
| `class function CS: LongInt; static` | 1 | 2 |
| `class function CN: LongInt` | 10 | 20 |
| `function Inst: LongInt` (instance) | 200 | 200 |

**Instance helper methods dispatch. Class-level helper methods never do**, and
`static` is not the discriminator. The defect is helper lookup for a class-level
member reached through `TClass.Method`.

### Why the "already correct" row must not be trusted as a control

`gen-TTest2 = 3` matches fpc, and the old summary leaned on it to warn that a
fix must not widen helper lookup. The warning is right; the evidence was not.
pxx answers 3 because it applies **no helper in any scope** — rows 3–5 — so that
row cannot show that a template-vs-specializing-scope rule exists, and a dispatch
fix will flip it to 4 with nothing holding it. Assert it before changing
dispatch, or the fix will appear to cause a regression it merely revealed.

fpc answering **4** for `TTest2.Test` and **3** for `specialize DoTest<TTest2>`
— same class, same helper, same program — is the real evidence that fpc resolves
a template body in the TEMPLATE's declaration context. That generics question is
genuine, and it is not measurable until helpers are applied at all.

Handed to frankZ whole; the slug now names something this is not.

## 2026-09-09 (frankZ) — re-measured before starting, and the assertion is landed

frankS's boundary holds. I rebuilt the probe from scratch rather than reuse
theirs — a second reading only counts if it can fail differently — and it agrees
on the conclusion while **disagreeing on one row's numbers**.

At `4d1b041a7fc9` (and unchanged from `92aba669db31`), `test/uclshelperdispatch.pas` + `test/test_a_class_helper_on_a_class_level_method.pas`,
both compilers run on the *same* two files:

| row | pxx | fpc 3.2.2 |
| --- | ---: | ---: |
| `gen-TTest` | 1 | 2 |
| `gen-TTest2` | 3 | 3 |
| `inunit` | 1 | 2 |
| `plain-TTest` | 1 | 2 |
| `plain-TTest2` | 3 | 4 |
| `classfn-nonstatic` (`class function CN`) | 10 | 20 |
| **`instance` (`function Inst`)** | **400** | **400** |

Confirmed: class-level helper members are never applied, `static` is not the
discriminator, three of the rows contain no generics, and `gen-TTest2 = 3` is
accidental — `plain-TTest2` is the same class, helper and program with generics
removed and pxx answers 3 there too.

### THE "ROW THAT DIFFERS" WAS MY ERROR, NOT THEIRS — corrected same day

I recorded the instance row as 400/400 against frankS's 200/200 and wrote that
theirs was the weaker measurement. **It is not. The two probes number the
opposite way round** — in frankS's, the class's own `Inst` returns 100 and the
HELPER returns 200; in mine the class returns 200 and the helper 400. So their
`200/200` and my `400/400` are the same reading: both compilers applied the
helper, the strong version, the one that makes this a boundary.

I read 200 as "the class's own" because 200 is the class's own **in my file**,
and never checked theirs. The reasoning I applied was sound and the premise was
invented: a row whose expected value collides with the failure value proves
nothing, which is this ticket's own warning two sections up — it just was not
true of that row. **Hedging the inference while inventing the premise** is the
exact shape CLAUDE.md names under "HEDGE THE PREMISE, NOT JUST THE INFERENCE",
and the visible care made the wrong half read as the checked one.

Left in place rather than deleted, because the corrected claim matters: an
`instance 400/400` row does not match any file frankS ran, and anyone comparing
the two write-ups needs to know why the numbers differ. **The conclusion was
never in doubt and was theirs.**

### Assertion landed first, as promised

`test/test_a_class_helper_on_a_class_level_method.pas` pins all seven rows with
its `.expected` as a **snapshot, not a specification** — five of the seven record
a wrong answer on purpose. Its header carries the table above and states what
each row becomes when dispatch is fixed: five turn correct (1→2, 1→2, 1→2, 3→4,
10→20) and **`gen-TTest2` turns wrong at 4 against fpc's 3**. That flip is the
second defect being revealed, not caused, and it is the point of landing this
before touching dispatch.

Wired in the Makefile beside `test_class_helper_for_a_class`, with `-Futest`.


## Resolution (2026-09-09, frankZ) — four loops, and the comment said two

The fix is two lines of behaviour in two places, and finding the second place was
the whole job.

`ClassHelperRecFor` exists so a helper redirect cannot drift between member-lookup
sites. Its own comment named **two** such loops. There are **four**, and the two
it did not name are the class-level ones:

| site | asked ClassHelperRecFor? |
| --- | --- |
| `pasparser_lval.inc:2699` — designator loop, INSTANCE | yes, unconditionally |
| `pasparser_lval.inc:5478` — ParseClassRecordSelectors, INSTANCE | yes, unconditionally |
| `pasparser_lval.inc:1486` — metaclass arm, CLASS-LEVEL | **only as a fallback** |
| `pasparser_expr.inc` type-name factor, CLASS-LEVEL | **never** |

The fallback is the subtler of the two: it consulted the helper only when the
class had **no** member of that name, so a helper could *add* a class method and
never *override* one. That is not FPC's rule, and `ClassHelperRecFor`'s comment
says so three lines above the call — the walk INTERLEAVES, helper-then-own at
each class up the chain, which is exactly why it returns `recId` unchanged when
the class's own member wins. Asking it first is therefore free.

The comment was not a documentation slip. **It was the defect, written down.**
The two loops it named were correct, so the sentence sampled true.

### Two arms, and only one of them is an expression

`TTest.CS` inside a `WriteLn` is a FACTOR; `TTest.Touch;` is a STATEMENT. They
are different parser arms and each needed its own edit. Measured, because the
first edit looked inert: with only the `pasparser_expr.inc` arm fixed, seven of
eight rows were already correct and `stmt-touch` still answered 1. A test made
of expressions cannot see the statement arm, and I nearly deleted a correct
change as dead code on exactly that evidence. The `stmt-touch` row exists so the
next person does not.

### Eight rows, seven matching fpc

`gen-TTest` 2, `inunit` 2, `plain-TTest` 2, `plain-TTest2` 4,
`classfn-nonstatic` 20, `instance` 400, `stmt-touch` 2 — all equal to fpc 3.2.2
on the same two source files.

### The eighth, and it is the point of the pin

`gen-TTest2` is now **4** against fpc's **3**. That row was pinned at 3 in
`17a0e4bd6`, before dispatch was touched, with its expected value recorded as
"currently correct for the wrong reason" — frankS's request, and their call was
right. pxx answered 3 by applying no helper anywhere, not by excluding the
specializing program's helper, and `plain-TTest2` (same class, helper and
program, generics removed: 3 here, 4 in fpc) is what proves it.

Split out as
[[bug-p-a-generic-template-body-is-resolved-in-the-specializers-scope-not-its-own]].
The constraint is recorded there and in the test header: **do not narrow helper
dispatch to chase it.** `gen-TTest` is the same template and must answer the
template unit's helper, so a fix that applies fewer helpers takes it down too.
It is a SCOPE rule — resolve a specialized body's names where the template was
declared — not a dispatch rule.

### And a correction that ran the other way

I told frankS their instance row (200/200) was the weaker of the two possible
measurements. It was not — their probe numbers the class's own `Inst` at 100 and
the helper at 200, so 200/200 says both compilers applied the helper, exactly as
my 400/400 does. I compared their numbers against MY probe's numbering without
reading theirs. Their conclusion, their evidence, and both were right.

## Log
- 2026-09-09 — resolved; this names the commit that carried the resolve, which is not always the one that carried the change — commit PENDING-COMMIT.
