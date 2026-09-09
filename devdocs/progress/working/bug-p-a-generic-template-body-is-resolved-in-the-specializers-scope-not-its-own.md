---
track: P
prio: 45
type: bug
blocked-by: []
status: working
owner: frankH
found-by: frankS
created: 2026-09-09
summary: "A generic routine's body resolves names in the SPECIALIZING scope, so a `class helper` declared by the specializing program reaches inside a template imported from another unit. `specialize DoTest<TTest2>` answers 4 (the program's TTest2Helper) where fpc 3.2.2 answers 3 (TTest2's own method). ONE ROW, and it is asserted in test/test_a_class_helper_on_a_class_level_method.pas as a KNOWN DIVERGENCE with the other seven rows around it as the constraint. THE EVIDENCE THAT THIS IS REAL AND NOT A PREFERENCE is entirely inside fpc: it answers 4 for `TTest2.CS` and 3 for `specialize DoTest<TTest2>` -- SAME class, SAME helper, SAME program -- so fpc really does bind a template body's names in the TEMPLATE's declaration context. Two-phase lookup. It was NOT MEASURABLE until 2026-09-09: pxx applied no class-level helper in any scope, so it answered 3 by applying nothing, and the row looked correct. DO NOT FIX BY NARROWING HELPER DISPATCH -- the seven rows beside it are what that would break."
---

# The shape

`test/uclshelperdispatch.pas` declares `TTest`, a `class helper for TTest`, and
`generic function DoTest<T: TTest>: LongInt` whose body is `Result := T.CS`.
`test/test_a_class_helper_on_a_class_level_method.pas` declares `TTest2 =
class(TTest)` with **its own** `CS` (3) and a `class helper for TTest2` (4).

```
row               pxx   fpc 3.2.2
specialize DoTest<TTest2>    4     3      <- this ticket
TTest2.CS                    4     4      <- agrees, and is the control
```

Same class, same helper, same program, and the two rows differ **in fpc**. That
is the finding: the only thing separating them is that one call goes through a
template body imported from another unit. fpc binds the body's names where the
template was DECLARED; pxx binds them where it is SPECIALIZED.

## Why this could not be seen before 2026-09-09

pxx answered 3 and that matched. It matched because pxx applied no class-level
helper **anywhere** — there was no exclusion rule doing the work, just nothing
happening. `TTest2.CS` in the same program answered 3 as well, against fpc's 4,
which is what settles it.

`bug-p-a-generic-routine-body-does-not-see-its-own-units-class-helper` fixed
class-level helper dispatch (four member-lookup loops, two of which never asked
`ClassHelperRecFor`). The moment helpers were applied at all, this row flipped to
4 with nothing to stop it — which was **predicted before the fix landed** and
pinned at 3 in its own commit (`17a0e4bd6`) so the flip would read as a defect
revealed rather than caused. frankS called it; the pin is theirs.

## The constraint on any fix

**Do not narrow helper dispatch.** Seven rows in the same file depend on
class-level helpers being applied: `gen-TTest` (2), `inunit` (2), `plain-TTest`
(2), `plain-TTest2` (4), `classfn-nonstatic` (20), `instance` (400),
`stmt-touch` (2). A fix that makes `gen-TTest2` answer 3 by applying fewer
helpers takes `gen-TTest` down with it — `gen-TTest` is the *same template* and
must answer the TEMPLATE unit's helper.

So the fix is a SCOPE rule, not a dispatch rule: while resolving a specialized
body, helper lookup must see the helpers visible at the template's declaration
site, not those visible at the specialization site. `gen-TTest` = 2 and
`gen-TTest2` = 3 are the same rule read on two inputs.

## Corpus

`library_candidates/fpc-testsuite/tests/test/tgenfunc19.pp` asserts exactly these
two rows (`Halt(1)` on the first, `Halt(2)` on the second) and is currently
blocked on this one row alone.
