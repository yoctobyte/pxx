---
track: N
prio: 70
type: bug
---

# `cb = lambda ...` then `cb(x)` compiles and does NOTHING

A **lambda** assigned to a plain local/global name and then called is a silent
no-op. No diagnostic, no crash — the call simply does not happen.

The `def` half of this is FIXED (the assignment RHS now goes through
PyMakeFuncValue, so `g = hi; g(5)` runs `hi`). What is left is the lambda:

```python
g = lambda x: print("got", x)
g(5)            # nothing
```

And the ZERO-argument form does not even parse:

```python
g = lambda: print("plain")
g()             # error: expected expression
```

## What DOES work (so the dispatch itself is fine)

A callable reached through a **subscript** works, because the subscript's result
is typed `tyVariant` and therefore takes the dynamic-call path:

```python
funcs = [hi];  funcs[0](7)      # ok
d = {"a": hi}; d["a"](8)        # ok
f2 = d["a"];   f2(9)            # ok — f2 IS a variant
```

## Where it goes wrong

`ParsePostfix` (parser.inc ~12386) turns `<expr>(` into `PyMakeDynCall` **only
when `ASTTk[CurASTNode] = tyVariant`**.

`PyParseLambdaStub` (pyparser.inc ~3582) yields **`tyPointer`** on both of its
paths — the lifted one (`pyboundfn_new` + binds) and the pyeval-closure
fallback (`pyclosure_src_new`) — because both helpers return a Pointer. So the
local is typed pointer, the postfix loop never fires, and the call is dropped.
In an ARGUMENT position the same pointer is boxed into the callee's
`const x: Variant` parameter, which is why `command=lambda: ...` works and
`g = lambda: ...; g()` does not.

Fix sketch: box the lambda value into a variant so the expression's type is
`tyVariant`. Doing it inside `PyParseLambdaStub` changes what every argument
position receives (they currently get a pointer and rely on the parameter
coercion), so either box there AND check the arg paths, or box only at the
assignment site — note `PyCoerceAssignmentRHS` does NOT box pointer -> variant
today, so that path needs the boxing call added explicitly.

The `def` case was fixed by calling `PyMakeFuncValue` from the plain
`NAME = expr` RHS branch (pyparser.inc ~10010) — the same hook a lambda fix
would sit next to.

## State of the call side (MEASURED 2026-07-29, an earlier note here was wrong)

There is no `pyvar_call0..3`; that helper was proposed, never written. What
`PyMakeDynCall` actually emits is `pyvar_callee_addr(v)` + `AN_CALL_IND` on the
result, plus two ternary guards bolted on top: tag 9 (pyeval closure, 1 arg) →
`PyClosureCall1`, and tag 8 (function value) → `pybound_callv<n>`, the latter
added by the def-value fix. `pyvar_callee_addr` now unwraps a tag-8 pair to its
Code, so a receiver-less function value is callable at any arity.

Still true: once `g` is typed variant the call site fires. What it will NOT yet
dispatch is a lambda's payload — a pyeval closure object or a lifted bound-fn
object reached as a bare POINTER (tag 7/0, not tag 9), which the guards do not
test. `pycall_value` (pyeval.pas) is the one routine that already discriminates
all four shapes; a result-keeping `pyvar_callv0..3` in its image is the missing
piece.

## Gate

`make test-nilpy` + self-host fixedpoint, plus the four snippets above matching
CPython.

## Log
- 2026-07-29 — resolved, commit 4cb96a3b6.
