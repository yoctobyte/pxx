---
track: N
prio: 75
type: bug
---

# A nested def's non-integer result is read as a number — silent garbage

Supersedes the diagnosis in
[[bug-nilpy-closure-capture-assigned-later]]: captures were a red herring. The
failure has nothing to do with capturing and everything to do with the RESULT
TYPE of a def declared inside another def.

## The matrix (each line diffed against CPython)

```python
def outer():
    def inner():
        return "big"
    ...
```

| what the enclosing body does with it | pxx | CPython |
| --- | --- | --- |
| `print(inner())` | `big` | `big` |
| `s = inner()` then `print(s)` | `big` | `big` |
| `s = inner()` then `return s` | **-381681640** | `big` |
| `return inner()` | **wild integer** | `big` |
| the same def at TOP level, `return top()` | `big` | `big` |
| a nested def returning an INT, `return inner()` | `7` | `7` |

So: the value itself is fine, and printing it is fine. Handing it back out of
the ENCLOSING function is what corrupts it, and only when it is not an integer.

## Cause

`PyInferDefRetType` decides the enclosing def's result while its body is still
unparsed. A nested def has no registered signature at that moment — only
top-level defs are hoisted (`PyRegisterDefShells` scans at depth 0) — so
`return inner()` cannot be typed and falls to the tyInteger default. The
enclosing function is then a function returning Integer, and the string handle
it stores is read back as a number.

The earlier `get(...).split("x")` wall was the same default from the other side.

## Attempts that did NOT fix it (all reverted)

1. `cur = tyUnknown -> tyVariant` in PyInferDefRetType. Landed and kept (it is
   right on its own), but it does not reach this case.
2. Accepting a `tyVariant` answer from the "chase the assignment" pass, which
   currently rejects it as a non-answer.
3. Treating an RHS that calls a name with no registered signature as dynamic.

None changed the output, so the deciding path is not the chase. Next step:
instrument `PyInferDefRetType` for the enclosing def and see what it actually
returns and from which branch — then either register nested-def shells before
the enclosing signature is decided (the real fix: it makes `return inner()`
typable rather than dynamic), or make the enclosing result variant and verify
the store boxes (a variant result carries a string correctly today, tested).

## Why this matters beyond songformatter

Returning the result of a helper defined inside the same function is ordinary
Python. The failure is silent and the value looks like a plausible number.
