---
track: P
prio: 70
type: bug
summary: "test_conformance_1's expected output still encodes the OLD Variant-typecast behaviour: it asserts `v int=1` where `v := 123`. 24204e10d made `Integer(v)` convert rather than reinterpret, so the compiler is now right and the expectation is wrong — and it holds every full tier RED."
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
