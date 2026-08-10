---
track: N
prio: 45
type: bug
summary: "A lambda with 2+ parameters still lowers to a pyeval SOURCE closure and is re-walked per call — the lift is gated on nParams <= 1 because the bound-fn bridge passes one argument. Correct answers, ~7x the per-call cost."
---

# Multi-parameter lambdas are still interpreted

- **Type:** bug (performance) — **Track N** (`pyparser.inc`, `PyParseLambdaStub`)
- **Filed:** 2026-08-10, as the recorded remainder of
  [[bug-nilpy-every-lambda-is-interpreted-instead-of-compiled]], which fixed the
  1-parameter case.

## Measured

```python
f = lambda a, b: a + b        # 7   — correct
g = lambda a, b, c: a * b + c # 10  — correct
```

Answers match CPython. But the bodies are still shipped as source text and run
by the tree-walker:

```
strings <bin> | grep -c '^return '   ->  2      (one per lambda)
```

Zero for a 1-parameter lambda since the parent fix. Expect the same ~6.9 µs vs
1.0 µs per-call gap measured there.

## Why it is gated

`PyParseLambdaStub`'s lift is guarded by `nParams <= 1`. The reason is the
bridge: `pyboundfn_callv(objptr, a0, res)` passes exactly **one** argument, and
a lifted proc reserves parameter 0 for the lambda's own argument with every
capture bound after it. A second own parameter has nowhere to ride.

`pyboundfn_callvn(objptr, a0, a1, a2, ...)` already exists — the multi-argument
bridge is there. What is missing is the lowering choosing it and the capture
layout reserving N own slots instead of 1.

## Why the priority is only 45

Every `key=` / `map` / `filter` / `sorted` callback is **1-parameter**, and that
is the overwhelming majority of lambdas in real Python — which is why the parent
fix took that case first. Multi-parameter lambdas show up in `reduce`, custom
comparators, and callback APIs that pass several values, so this is real but far
less hot.

## Fix direction

Reserve `nParams` own slots at the head of the lifted parameter list rather than
exactly one, bind captures after them, and route the call through
`pyboundfn_callvn`. The existing zero-parameter case (a dummy `$lamarg0` absorbs
the bridge's single argument) shows the slot bookkeeping is already
parameterised in shape, just not in count.

Watch `PY_MAX_CAPS`: own parameters and captures share the bound-slot budget, so
N own parameters reduce the captures a lambda can hold.

## Gate

The two lambdas above compiled (`strings ... | grep -c '^return '` = 0), answers
still matching CPython, the NilPy suite green, and self-host fixedpoint.
