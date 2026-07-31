---
track: N
prio: 30
type: feature
blocked-by: []
---

# `min(a, b, c)` / `max(a, b, c)` — only the 2-argument and iterable forms exist

Found by proactive CPython-diff sweeping.

```python
print(min(3, 1, 2))
```
CPython: `1`. pxx: compile error —
```
no overload of min matches these arguments
  argument types: (Integer, Integer, Integer)
  candidates:
    min(Variant, Variant)
    min(Int64, Int64)
    min(Double, Double)
    min(class)
    min(AnsiString)
```

`min`/`max` (`compiler/builtin/pylib.pas`) are ordinary overloaded Pascal
functions resolved through the normal call/overload machinery — there is no
special parser dispatch for them at all (unlike `enumerate`/`zip`, which get a
`PyExprMode`-gated `ParseFactor` branch). Only the 2-argument scalar overloads
and the `min(iterable)`/`max(iterable)` single-container form exist, so any
call with 3+ positional arguments has no matching overload.

## Fix direction (not attempted here)

Adding fixed-arity overloads (3-arg, 4-arg, ...) doesn't generalize — Python's
`min`/`max` accept any number of positional arguments. The clean fix is a
`PyExprMode`-gated special case in `ParseFactor` (mirroring the
`enumerate(xs)`/`zip(a, b)` value-form branches already there) that: on seeing
`min(`/`max(` with 3+ comma-separated top-level arguments ahead (via the
existing `CountCallArgsAhead` helper) and no user shadow (`FindSym('min') <
0`), parses each argument and folds them through the EXISTING, already-correct
2-argument overload left-to-right — `min(a, b, c)` → `min(min(a, b), c)` —
rather than reimplementing overload resolution. The 2-arg case's own
argument-type dispatch (Int64/Double/Variant, matching `OverloadArgRank`)
already picks the right concrete function per pair, so the fold only needs to
chain calls, not re-derive typing.

Not attempted this pass — time-boxed during a broader CPython-diff sweep;
building the AST-node-chaining call construction safely (reusing whatever the
ordinary 2-arg call-parsing path already builds) needs its own careful look
rather than a rushed patch to shared `ParseFactor` call-dispatch code.

## Gate

A `.npy` case with `min`/`max` at 2, 3, 4+ positional args, mixed
int/float/string arguments, diffed against CPython, gated in `test-nilpy` +
`--tier quick` + self-host byte-identical.
