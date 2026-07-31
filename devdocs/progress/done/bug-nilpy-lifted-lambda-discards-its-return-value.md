---
track: N
prio: 60
type: bug
---

# NilPy: a lifted lambda always discarded its own return value

Found while researching
[[bug-nilpy-callable-value-abi-sorted-key-and-builtins]] — not previously
documented as its own ticket, and distinct from anything `sorted()` does.

## Repro

```python
def outer():
    h = lambda s: len(s)
    return h("abcde")
print(outer())          # CPython: 5    pxx (before): None
```

A lambda whose body is a single call gets LIFTED to a real compiled proc
(`feature-nilpy-lambda-compiled-closure`'s `PyCompileLambdaBody`), not
interpreted. The lifter was first built for a side-effect-only handler shape
(`lambda: on_click()`) and its body-compile treated the parsed expression as
a discard-only statement — "the expression IS the statement" — so `$pyresult`
was never written and stayed at its zero-initialised None. This has nothing
to do with `sorted()`, `map`, or any caller: calling a lifted lambda directly
and reading its value answered None unconditionally, for every value-shaped
lambda that happened to qualify for lifting.

## Fix

Wrap the parsed expression in a real `AN_EXIT` node — exactly what a written
`return <expr>` produces — so it stores into `$pyresult` through
`CompileAST`'s ordinary return-coercion path, the same one every other
`return` in the compiler already uses.

## Known remaining gap

A `tyClass`/`tyRecord` result is excluded: `lambda s: log.append(s)` (append
returns `Self`) boxed into `$pyresult` and released by a caller that discards
it drove the SAME captured `log` to refcount 0 and freed it out from under
the enclosing scope that still owned it — traced with `-dPXX_OBJTRACE` (4
retains / 5 releases where the scalar/string case balances at 2/2). This is
an aliased-captured-object ownership gap around the bound-fn call bridge —
the same territory
[[bug-nilpy-bound-fn-closure-objects-are-never-freed]] already tracks, not
something to special-case away here. The side-effect-only shape (returning
`Self`, discarded by the caller) keeps its old discard-only behaviour,
unchanged and still correct.

## Gate

`make test-nilpy` + self-host byte-identical, plus a `.npy` covering a
value-returning lifted lambda (int, string, arithmetic, `.upper()`) AND the
side-effect-only shape, diffed against CPython.

## Resolved

Fixed and gated green — commit bd6d7ba9085d7f0528c7cd6339e0442f19b283c3.
Regression: `test/test_nilpy_lifted_lambda_return_value.npy`.

## Log
- 2026-07-31 — resolved, commit bd6d7ba9085d7f0528c7cd6339e0442f19b283c3.
