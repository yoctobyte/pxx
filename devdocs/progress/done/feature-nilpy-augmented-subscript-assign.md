---
summary: "nilpy: augmented assignment to a subscript — d[k] += 1, xs[i] += 5 — does not parse"
type: feature
track: N
prio: 55
---

# nilpy: `d[k] += 1` is not an lvalue

- **Type:** feature (Nil-Python frontend, assignment lowering) — **Track N**
- **Status:** done
- **Opened:** 2026-07-26 — found while adding `collections.Counter`
  ([[feature-nilpy-collections-and-string-methods]]); pre-existing, reproduced on
  the pinned stable, unrelated to Counter.

## Repro

```python
d = {"a": 1}
d["a"] += 1        # error: assignment target is not an lvalue

xs = [1, 2]
xs[0] += 5         # error: assignment target is not an lvalue
```

Plain subscript assignment is fine — `d["a"] = 1` and `xs[0] = 5` both work — and
so is `x += 1` on a simple name. Only the augmented form with a subscript target
fails.

## Why it matters

`counts[k] += 1` is the single most common counting idiom in Python, and
`xs[i] += v` is the most common accumulate. A Counter is far less useful without
it: the whole point of a missing key reading as 0 is that `c[k] += 1` needs no
seeding.

## Shape

Desugar `target[key] op= value` to a read-modify-write of the same subscript,
evaluating the target and key expressions ONCE (Python evaluates them once; a
naive textual expansion would evaluate a call in the key twice). All the augmented
operators, not just `+=`.

## Note on the diagnostic

The error is reported one line PAST the offending statement (a 3-line file reports
line 4). Line attribution in these diagnostics is unreliable in general — see the
note in [[bug-nilpy-stdlib-name-binds-pascal-unit]], where an error inside a used
unit is reported against the main file with a fictional line number.

## Gate

`make test-nilpy` green with a `.npy` case covering dict, list and Counter targets
and every augmented operator, diffed against CPython, + `--tier quick` +
self-host byte-identical.

## CLOSED — found already fixed

Re-checked directly against current HEAD: `d["a"] += 1`, `xs[0] += 5`, a
`Counter` target, and `-=`/`*=` on both dict and list subscripts all work and
match CPython. Whatever landed the general subscript-assignment lowering
work since this was filed (2026-07-26) evidently covered the augmented form
too — no specific commit identified, and none was worth archaeology-hunting
for since the behavior is simply correct now.

No test existed to guard this shape, so one was added rather than closing on
faith alone: test/test_nilpy_augmented_subscript_assign.npy. Gate: make
test-nilpy green, self-host fixedpoint, testmgr --tier quick.

Ticket closed.

## Log
- 2026-07-31 — resolved, commit 412e08b6d.
