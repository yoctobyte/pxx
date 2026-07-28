---
track: N
prio: 70
type: bug
---

# An import inside a function body — and the fix that silently emptied the body

songformatter's `convertrawtext.py:1911` imports its render backend inside the
method that draws the preview:

```python
def refresh(self):
    ...
    import tkinter as tk
    from render_backend import TkCanvasBackend, PAGE_W, PAGE_H
```

Ordinary Python. pxx reports `expected newline after statement`, and the line it
names is far away (84) because the failure surfaces from a pre-pass.

## Cause, and the trap in fixing it

`PyParseImportRun` ends every import with `PySkipNewlines`. At module level that
is right; inside a BLOCK the newline terminates the statement and belongs to the
block parser, so the next line reads as a continuation.

Suppressing that skip for an in-body import (a `PyImportInBody` flag around the
statement-level call) makes the file COMPILE — and the enclosing function then
does nothing at all:

```python
def go():
    print("before")
    import tkinter as tk
    print("after")

go()          # CPython: before/after.  pxx with that fix: NOTHING printed
```

Not even the statement BEFORE the import runs, so the whole body is being
dropped rather than truncated at the import. Reverted: a compile error is better
than a function that silently does nothing.

## Next step

Find where the body goes. The def body is compiled from stored token positions
in a deferred pass, so the likely culprit is the import run consuming or
repositioning tokens that the deferred parse then reads — compare `TokPos`
before and after the in-body `PyParseImportRun` against the def's recorded body
span. Fix that first; the newline handling is the easy half.

## Log
- 2026-07-28 — resolved, commit 5174d000e.

## Resolution

Already fixed by earlier NilPy work that did not move the ticket. Re-verified
2026-07-28 at 5174d000e: the repro above matches CPython exactly.
