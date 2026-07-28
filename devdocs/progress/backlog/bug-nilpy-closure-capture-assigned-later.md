---
track: N
prio: 60
type: bug
---

# A nested def cannot capture a name the enclosing function assigns LATER

Python binds a closure at CALL time, so this is ordinary:

```python
def outer():
    def inner():
        if flag:            # captured, bound when inner() runs
            return "yes"
        return "no"
    flag = True
    return inner()

print(outer())              # CPython: yes
```

pxx: `error: undefined variable (flag)`. Moving `flag = True` ABOVE the nested
def compiles and runs correctly, which is the whole difference.

Found in songformatter's `convertrawtext.py:1168`
([[feature-demo-songformatter-pxx-target]]): `printHeaders()` reads `firstpage`,
which `format_song_text_as_pdf` assigns further down.

## Why the obvious fixes do not work

The capture list is built from a token scan when the def is met, and a name is
captured only when `FindSym` resolves it to a local or parameter of the
enclosing scope (`pyparser.inc`, the `nCaps` loop). Two attempts, both reverted
because neither changed the error:

- materialise the name from `PyLocals` (the enclosing scope's collected-locals
  table) when `FindSym` misses — the entry is not there yet at that point;
- scan the enclosing body forward for a later `name =` and allocate a variant
  local for it.

That both had no effect says the failure is not in the capture list at all:
a nested def's body is parsed in a DEFERRED pass (`PyPendNest*`, drained in
ParsePyUnit / the def-body queue), and by then the enclosing function's symbols
have been rolled back, so the body's own name resolution is what fails. The fix
therefore belongs where the deferred body is parsed — the captured names must be
in scope as the trailing parameters they were registered as, and a name the
enclosing scope will assign has to be added to the capture list BEFORE the body
is queued.

## Gate

`make test-nilpy` plus a `.npy` with a capture assigned after the nested def,
and one assigned before (which must keep working), diffed against CPython.
