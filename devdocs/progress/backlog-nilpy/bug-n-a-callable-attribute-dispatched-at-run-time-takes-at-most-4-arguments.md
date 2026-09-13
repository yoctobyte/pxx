---
slug: bug-n-a-callable-attribute-dispatched-at-run-time-takes-at-most-4-arguments
title: a callable attribute dispatched at run time takes at most 4 arguments
summary: >
  `o.thing(a, b, c, d, e)` where `thing` is a CALLABLE FIELD rather than a
  method, on a receiver whose class is not declared in this compilation unit,
  raises `takes at most 4 arguments` at run time. The METHOD arm of that same
  path became arity-free on 2026-09-13 (pydyn_methl takes a TPyList); the
  callable-field arm still funnels into pyvar_callv0..4, which is a ladder with
  no fifth rung. The refusal is DELIBERATE and replaced a silent truncation --
  the old `else` arm called pyvar_callv4 and dropped the rest -- but a refusal
  is still a refusal. The fix is a list-taking pyvar_callv, which is a different
  subsystem with its own consumers.
track: N
type: bug
prio: 40
owner: unassigned
status: open
---

## How it was reached

Not by a report. Lifting the frontend's 4-argument cap on run-time dispatch
(`MAX_DYN_ARGS`, so lekkerzeilen's `gl.tex_image_2d(target, fmt, w, h, fmt,
data, level=at)` could compile) made an arm REACHABLE that could not previously
be entered with five arguments: PyDynMethL's fallback for a receiver whose
attribute is a callable value, not a method.

`case nargs of 0..3: ... else pyvar_callv4(...)` was exactly right while the
frontend capped at four — `else` could only mean four. With the cap lifted it
would have meant "five or more, silently pass the first four", which is the
plausible-wrong-value trade the cap's own comment was written to avoid. So it
raises instead, and this ticket is the honest record of what that costs.

## Repro

A callable FIELD, not a method, on a receiver from another module:

```python
# holder.py
class Box:
    def __init__(self):
        self.thing = lambda a, b, c, d, e: a + b + c + d + e

def make():
    return Box()
```

```python
import holder
o = holder.make()
print(o.thing(1, 2, 3, 4, 5))
```

CPython prints 15. pxx raises
`thing() is dispatched at run time through a callable attribute, which takes at
most 4 arguments`.

## The fix

`pyvar_callv` needs a list-taking form the way `pydyn_meth` just got one —
`pyvar_callvl(cb, args: TPyList)` — and then PyDynMethL's callable arm loses its
`case` entirely. Both `pyvar_callv_kw` and the rungs stay as wrappers, for the
reason the pydyn rungs stayed: they are a public builtin interface.

Note the neighbouring refusal is a DIFFERENT one and is not this ticket: a
KEYWORD argument through a callable field is refused because there are no
parameter names to bind against, which is correct and intended.
