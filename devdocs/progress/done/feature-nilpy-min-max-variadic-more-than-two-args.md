---
track: N
prio: 30
type: feature
blocked-by: []
status: done
owner: claude-AN
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

## Done 2026-08-03

The ticket was partly stale: all-Variant **3- and 4-argument** overloads had
since been hand-written into pylib.pas, so `min(3, 1, 2)` and `min(3, 1, 2, 0)`
already worked and only **5+** still had no candidate — which is exactly the
"adding fixed arities one at a time never terminates" the ticket predicted,
caught mid-sequence.

Implemented as the ticket's fix direction, with one change of substrate:
`PyParseVariadicMinMax` (pyparser.inc), dispatched from `ParseFactor` under
`PyExprMode`, folds left-to-right through the EXISTING 2-argument overload —
`min(a,b,c)` = `min(min(a,b),c)`. Each pair resolves through
**`MatchProcCall(nm, 2, argTypes, False)`** on the two operands' actual types,
NOT `FindProc(nm)`: `FindProc` returns one proc and never consults overloads
(`project_findproc_by_name_ignores_overloads`), which would have silently
picked a single arm for every operand shape. Folding keeps the int fold an int
rather than boxing through the Variant arity overloads.

### The guard is the part that needed measuring

The branch is claimed only when `CountCallArgsAhead >= 3` **and**
`PyAnyProcWithArity(name, n)` is false. Without the second test the fold would
steal calls an ordinary overload can already serve — pylib's own 3/4-arg
overloads, and a NilPy `def min(a, b, c, d, e)` over the builtin. Verified: a
5-argument user shadow still returns its own answer (100), and the fold takes
over only where nothing of that arity exists.

Measuring that guard turned up a **separate, pre-existing** bug, filed as
[[bug-nilpy-user-def-loses-to-pylibs-variant-overload-at-the-same-arity]]: a
user `def min(x, y, z)` compiles and is then silently not called, because
pylib's all-Variant 3-arg overload outranks it. The fold provably cannot reach
that call (pylib has arity 3, so the guard rejects the branch), and the same
shadow at 2 and at 5 arguments works — it is an overload-ranking gap, not this
change.

### Verified

`test/test_nilpy_min_max_variadic.npy` (new, registered in both `test-nilpy`
Makefile sites): min/max at 3, 4, 5 and 7 arguments over ints, floats and
strings; expression arguments; variables; the 1- and 2-argument and iterable
forms unchanged; and the 5-arg user shadow. All 17 lines byte-identical to
CPython. `tools/gate.sh quick` GREEN (self-host fixedpoint + `--tier quick` +
FPC seed canary).

## Log
- 2026-08-03 — resolved, commit aaf5c89a3.
