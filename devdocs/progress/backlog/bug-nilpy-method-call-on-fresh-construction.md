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
