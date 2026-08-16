---
track: N
prio: 40
type: bug
blocked-by: []
summary: "`1.5 ** f()` called f() TWICE — the float `**` route hands its exponent to both pypow_dom and the RTL's Power, and an AST node referenced twice is emitted twice. math.pow's own lowering already parks its exponent in a temp for exactly this reason."
---

# The float `**` operator evaluates its exponent twice

Found 2026-08-16 while reading `PyMakePow` for
[[bug-nilpy-float-overflow-answers-inf-where-cpython-raises]] — not from a
report. Nothing failed; the VALUE was always right.

## Repro

```python
n = 0
def f():
    global n
    n = n + 1
    return 2.0
print(1.5 ** f())
print("calls:", n)      # CPython 1    NilPy 2
```

## Cause

`PyMakePow`'s static float route sends the base through `pypow_dom` (the guard
that refuses a negative base with a fractional exponent by name) and then calls
the RTL's `Power`. The **exponent reaches both**: once inside the guard's
argument list, once as `Power`'s second argument. The AST is a tree, so a node
referenced twice is EMITTED twice, and `CloneAST` does not help — a clone is a
second subtree, hence a second call.

`math.pow`'s lowering, in the same file, already parks its exponent in a temp
via `PyEvalOnce` and its comment says exactly why. This arm was written from
that one and did not copy the line. Same shape as every other entry in
[[project_nilpy_lvalue_vs_selector_path_must_both_know]]: one concept, N
independent sites, and the one that stays broken is the one nobody diffed.

## Fix

`ppExp := PyEvalOnce(ppExp);` before the guard's argument is built, in
`PyMakePow` (`compiler/pyparser.inc`).

## Why it can matter

Only side effects are observable — every value was already correct — so the
failure mode is a counter that double-counts, a generator advanced twice, a log
line printed twice. That is the same class as
`bug-c-a-struct-assignment-used-as-a-value-runs-its-rhs-twice`, and it is the
class the human-written test corpus does not catch, because tests assert values.

## Gate

`test/test_nilpy_pow_evaluates_operands_once.npy` — six spellings (static float
both ways round, base-only, augmented `**=`, `math.pow` which was already right,
and a variant receiver through `pypow_v`), each printing the call counter,
diffed against CPython. Plus the per-fix loop.
