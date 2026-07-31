---
summary: "nilpy: augmented assignment to a subscript — d[k] += 1, xs[i] += 5 — does not parse"
type: feature
track: N
prio: 55
---

# nilpy: `d[k] += 1` is not an lvalue

- **Type:** feature (Nil-Python frontend, assignment lowering) — **Track N**
- **Status:** working
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
