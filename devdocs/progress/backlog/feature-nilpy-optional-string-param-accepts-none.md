---
summary: "nilpy: passing None to an Optional[str] / str|None PARAMETER does not match the overload"
type: feature
track: N
prio: 50
---

# nilpy: `f(None)` where the parameter is `Optional[str]`

- **Type:** feature (Nil-Python frontend, Optional lowering) — **Track N**
- **Status:** backlog
- **Opened:** 2026-07-26 — found while adding PEP 604 unions
  ([[feature-demo-songformatter-pxx-target]]). PRE-EXISTING: reproduces on the
  pinned stable with the `Optional[...]` spelling, so it is not a union-specific
  problem.

## Repro

```python
from typing import Optional
def g(x: Optional[str]) -> str:
    if x is None:
        return "none"
    return x
print(g("a"), g(None))
```
```
error: no overload of g matches these arguments
  argument types: (Pointer)
```

`str | None` behaves identically, by design — unions get Optional's exact
treatment. RETURNING None from such a function works; only passing it in fails.

## Why

An `Optional[str]` parameter is typed AnsiString (Optional widens `str` to
AnsiString), and `None` arrives as a nil Pointer, which does not match. The
return path works because a return annotation widens further, to a real variant,
so None and a legitimate value stay distinct.

## Shape

Type an Optional PARAMETER the way an Optional RETURN is typed — a variant, so
None is VT_EMPTY rather than a nil pointer of the wrong type — or accept a nil
Pointer argument for an Optional-annotated string parameter. The first is more
consistent with what the return path already does.

## Gate

`make test-nilpy` green with a `.npy` case passing None and a real value to
Optional params of str / int / a class type, diffed against CPython, + `--tier
quick` + self-host byte-identical.
