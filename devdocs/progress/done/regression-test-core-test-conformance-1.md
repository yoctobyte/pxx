---
track: P
prio: 70
type: bug
summary: "test_conformance_1's expected output still encodes the OLD Variant-typecast behaviour: it asserts `v int=1` where `v := 123`. 24204e10d made `Integer(v)` convert rather than reinterpret, so the compiler is now right and the expectation is wrong — and it holds every full tier RED."
status: done
---

# test_conformance_1 asserts the bug that `fix(P): a typecast of a Variant CONVERTS` removed

- **Type:** bug (stale test expectation) — **Track P**, re-filed from the
  watcher's auto-stub by Track T (face 2). T owns the tool, never the bug: the
  judgment about which value is correct is the Pascal frontend's.
- **Found:** 2026-08-13T06:14:50Z by twatch on plexus, `full` tier.
- **Still red at HEAD** — re-verified 2026-08-13 10:00 (not just at the sha the
  callback was tagged to).

## The divergence

```
  ./compiler/pascal26 test/test_conformance_1.pas /tmp/test_conformance_1_26
  -v int=1        <- expected
  +v int=123      <- actual
```

Every other line of the 20-line expectation matches. The test source, at
`test/test_conformance_1.pas:142`:

```pascal
  { variant }
  v := 123;
  writeln('v int=', Integer(v));
```

## Diagnosis: the compiler is right and the expectation is wrong

The bisect range is 6 commits; only one of them touches semantics:

```
24204e10d fix(P): a typecast of a Variant CONVERTS, it does not reinterpret the record
```

That is exactly this construct. Before it, `Integer(v)` reinterpreted the
variant's storage and yielded `1` — which is not the value assigned, it is the
leading word of the variant record (the type tag). The expectation was recorded
from that output, so **the test has been asserting the bug since it was
written**: `v := 123; Integer(v)` must be `123`.

So this is not a regression. It is the fix arriving and the frozen expectation
disagreeing with it — the failure mode where a green suite has been certifying
wrong behaviour, and the red is the good news.

## Do

Update the expected string in the `test-core` recipe for
`test/test_conformance_1.pas`: `v int=1` -> `v int=123`. Confirm with

```
tools/testmgr.py --tier native --job 'test-core#src:test/test_conformance_1.pas'
```

Per `normalise-dont-special-case`'s sibling rule — *if you fix a bug on one arm
of a double case, grep for the sibling* — 24204e10d is worth grepping against
the rest of the corpus before closing: any other expectation recorded from a
Variant typecast has the same defect and is either red now or asserting the same
old behaviour on a path no test exercises.

## Why it was filed as a regression

The watcher cannot tell "the code broke" from "the expectation was always
wrong"; both are `red at sha X, green at sha Y`. That is not a defect in the
stub — the range it produced pointed straight at the cause. Recorded here
because it is the second instance today of a T-only red whose stub carried a
job name and a range but **no failing output**, which is the general gap noted
in [[bug-t-nilpy-isnumeric-red-at-T-not-reproducible-locally]]: enriching it
cost a local re-run that the report could have carried.

## ALREADY FIXED — closing the stale ticket, 2026-08-15

The expectation was corrected on 2026-08-13 by **9e204de32 `fix(A):
test_conformance_1's variant expectation encoded the OLD BUG`** — the same
diagnosis this ticket reaches, landed the day it was filed. The ticket was never
moved out of `backlog/`, so it stayed at the head of the ranked queue (effective
prio 70, the global top) for two days pointing at work that was done.

Verified at HEAD (self-hosted fixedpoint, e02105519): the recipe reads
`v int=123`, and `test/test_conformance_1.pas` output matches the full 20-line
expectation exactly.

**The sibling grep this ticket asks for, done rather than deferred.** Every test
whose expectation could have been recorded from the OLD reinterpret behaviour:

| test | verdict |
| --- | --- |
| `test_variant_typecast.pas` (25 rows) | matches its recipe exactly |
| `test_variant_typecast_strict.pas` (`--strict-fpc`, 10 rows) | matches exactly |
| `test_channel.pas` | compiles and runs; no typecast row in its expectation |

So no other expectation is carrying the old behaviour, and nothing else is
asserting it on an unexercised path.

**Worth keeping from this:** a `resolve` that never happens leaves a ticket at
the top of `next` indefinitely, and the ranker has no way to notice the work
landed — the commit message named the ticket's symptom but not its slug, so
nothing connected them. The board is the record; a fix that skips it stays
invisible to every later agent.

## Log
- 2026-08-15 — resolved, commit PENDING-COMMIT.
