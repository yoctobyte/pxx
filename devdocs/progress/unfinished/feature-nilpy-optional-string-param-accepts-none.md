---
summary: "nilpy: passing None to an Optional[str] / str|None PARAMETER does not match the overload"
type: feature
track: N
prio: 50
---

# nilpy: `f(None)` where the parameter is `Optional[str]`

- **Type:** feature (Nil-Python frontend, Optional lowering) — **Track N**
- **Status:** unfinished
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

## Recon 2026-07-31 — the repro has changed shape; still broken, differently

Re-ran the ticket's own repro on current HEAD. It no longer hits the compile
error ("no overload of g matches these arguments") — `g(None)` now COMPILES.
But the runtime answer is wrong in a new way:

```
print(g("a"), g(None))   # CPython: a none     pxx: a None
```

`g(None)` is being called (not rejected), but inside `g`, `x is None` does not
take the True branch — the function falls through to `return x`, and PRINTING
`x` renders the text `"None"` (four characters, capital N), not the identity
check's own None marker. So whatever coercion now lets the call through is not
the `pynone()` VT_EMPTY-boxing fix `IRLowerCallArg` already has for a VARIANT
parameter (`ir.inc` ~line 2208, "Python's `None` reaches here as the nil
POINTER literal... f(None) then printed 0") — that block is gated on the
PARAMETER being `tyVariant`, and `Optional[str]` maps to `tyAnsiString`
(PyAnnTypeAt), not variant, so it never fires here. Something ELSE now accepts
a nil-pointer argument against an `AnsiString` parameter and turns it into the
text "None" rather than a nil string handle — not yet located. `IRLowerCallArg`
is a very large, historically fragile function (each of its many special
cases documents a specific past regression); finding the exact coercion
without measuring it directly (PXXDBG a.ir on the call site, or bisecting
which recent commit changed this from a compile error to a silent wrong
value) risks a guess, which the project's own debugging playbook warns
against. Left for the next session with time to measure it properly rather
than patch blind.

Not fixed. Recon only — see above for what changed and what still needs
locating.
