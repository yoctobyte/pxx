---
track: N
prio: 70
type: feature
---

# NilPy: a nested def used as a VALUE (stored, passed, returned)

Split out of [[feature-nilpy-nested-defs]] when its two slices landed
2026-07-20. Nested defs now parse, nest to any depth, and READ enclosing locals
— but only when CALLED from inside the enclosing body.

```python
def make(k: int):
    def inner(m: int) -> int:
        return m + k
    return inner            # returning it — not supported
handlers.append(inner)      # storing it — not supported
```

## Why this is the harder half

Capture is implemented by appending the captured values as extra ARGUMENTS at
each call site, which only works because every call is lexically inside the
parent, where those names are in scope. A def escaping as a value has no such
call site: it needs the captured state to travel WITH it — a closure record
(code pointer + captured slots) rather than extra parameters.

That is a real feature, not an extension of the current one:

- a first-class function VALUE in NilPy at all (`Callable[...]` annotations
  exist in `PyAnnTypeAt`, so the type side has a start);
- a heap closure record, and the lifetime rule for it;
- Python's late binding: a closure reads the enclosing variable at CALL time,
  so a loop that defines one closure per iteration and mutates the loop
  variable has all of them see the LAST value — the famous surprise, and the
  thing a by-value capture at definition time gets wrong.

## Why it matters

uforth registers native words. If that registration stores the inner function
in a table rather than calling it inline, the current slice is not enough for
the corpus and this ticket is the real blocker.
Checked 2026-07-20 with an `ast` walk over `/home/rene/projects/uforth/uforth.py`:
of the references to inner-def names, **52 are calls and ~197 are value uses**
(249 name references total, which includes the call's own function reference).
So uforth STORES its natives far more often than it calls them inline — this
ticket, not the landed slice, is the corpus blocker. Priority raised to match
[[feature-nilpy-corpus-uforth]] accordingly.

## Gate

`test-nilpy` green + `--tier quick` + self-host byte-identical, with a returned
closure, a stored-in-a-list closure, and the loop-variable late-binding case,
all matching CPython.
