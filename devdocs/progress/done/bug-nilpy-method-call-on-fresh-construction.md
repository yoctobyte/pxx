---
summary: "nilpy: Cls().method() — a method call directly on a construction expression"
type: bug
track: N
prio: 45
---

# nilpy: `Cls().method()` does not parse

- **Type:** bug (Nil-Python frontend) — **Track N**
- **Opened:** 2026-07-27, writing the class-attribute test
  ([[feature-demo-songformatter-pxx-target]]).

## Repro

```python
class A:
    def get(self) -> int:
        return 5

print(A().get())        # error: unexpected token   near:  A  >>> get
a = A()
print(a.get())          # fine
```

Pre-existing: reproduces on the pinned stable, and is independent of the class
attributes and qualified-construction work that surfaced it.

## Cause

`PyClassCreate` returns the construction expression, but the intercept that
routes `ClassName(` to it does not continue through the postfix selector loop, so
a trailing `.method()` / `.field` / `[i]` has nothing to attach to. The Pascal
side does that continuation with `ParseLValueAST` / the selector loop; the NilPy
ctor intercept exits straight to the caller.

## Shape

After `CurASTNode := PyClassCreateExpr`, feed the node back into the postfix
selector loop instead of exiting — the same shape `PyParseStrMethod` uses to let
`s.upper().strip()` chain.

## Workaround until then

Bind the instance to a name first (`a = A()` then `a.get()`), which is what the
tests do.

## 2026-07-30: already fixed — closed with a test, not just a re-check

`A().get()` compiles and answers correctly today, on HEAD. The fix landed with
the construction-vs-receiver split in the assignment path (pyparser.inc names
this ticket in the comment: "`x = Cls().method(...)` is not a construction
ASSIGNMENT: the construction is the RECEIVER").

Verified across the positions the one-line repro did not cover — a constructor
with and without arguments, a string-returning method, two fresh constructions
in one arithmetic expression, and fresh constructions as list elements — all
diffed against CPython. Gated by
`test/test_nilpy_method_on_fresh_construction.npy` so it cannot silently regress
the way it silently fixed.

## Log
- 2026-07-30 — resolved, commit 83d708d74.
