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

## Third attempt: compiles, and produces GARBAGE

Skipping the DEDENT(s) that close the nested def before scanning forward for a
later `name =` (the earlier scan started ON them, so its depth went negative
immediately and it found nothing) does make the program compile — and it then
prints a wild integer instead of `yes`. The capture is passed as a trailing
argument at the CALL site, so materialising the local is not enough on its own:
the pre-allocated variant is not the symbol the later assignment writes, or it
is never initialised.

That is worse than the compile error and was reverted. Whatever the fix is, it
has to make the enclosing assignment and the capture agree on ONE symbol — which
is the same conclusion the deferred-body analysis above reaches, from the other
end.

## Gate

`make test-nilpy` plus a `.npy` with a capture assigned after the nested def,
and one assigned before (which must keep working), diffed against CPython.

## Fixed 2026-07-28

Both halves, and the ORDER mattered: every earlier attempt at the capture
"compiled and produced garbage", and that garbage was
[[bug-nilpy-nested-def-nonint-result-garbage]] underneath — the enclosing
function's result type, not the capture. With that fixed, materialising the
later-assigned local at capture time is enough, and
`capture_after`/`capture_before` both match CPython.

The lesson worth keeping: when a fix "works but returns a wrong value", suspect
a second bug below it rather than the fix.

## Log
- 2026-07-28 — resolved, commit pending.
