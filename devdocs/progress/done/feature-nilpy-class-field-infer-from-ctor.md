---
summary: "nilpy: infer a class field's type from the ctor parameter assigned to it"
type: feature
track: N
prio: 50
---

# nilpy: infer field types from `self.x = <param>`

- **Type:** feature (Nil-Python frontend, typing) — **Track N**
- **Status:** done
- **Opened:** 2026-07-26 — probing songformatter under nilpy
  ([[feature-demo-songformatter-pxx-target]]).

## Repro

```python
class Base:
    def __init__(self, n):
        self.n = n
```
-> `error: Nil Python: cannot infer the type of field self.n - annotate it
(self.n: int = ...)`

## Why it matters

This is THE shape of an ordinary Python class, so it blocks nearly every
class-using program that wasn't written with pxx in mind — including
songformatter's document/analysis classes. Annotating is a change to the source
we don't get to make in third-party code, and "compile the existing source
as-is" is the mission ([[frank2-mission-compile-real-world-asis]]).

## Shape

When a ctor parameter is annotated or has a typed default, propagate that type to
the field assigned from it. Where the parameter is untyped, the field can take the
variant type rather than erroring — the existing AST typing pass
([[feature-n-nilpy-ast-typing-module-scope]]) is the natural place. A dataclass
with defaults already works, which suggests the machinery is close.

## Gate

`make test-nilpy` green with a `.npy` case (inherited + overridden methods,
annotated and unannotated ctor params) diffed against CPython, + `--tier quick` +
self-host byte-identical.

## Log
- 2026-07-31 — resolved, commit 31ea7274fb78809178a254c9625542d1178a612f.
