---
track: N
prio: 80
type: bug
---

# SettingsEditor segfaults reading a bound method off a field

songformatter now COMPILES and RUNS as far as building its GUI, and dies here:

```python
class SettingsEditor(tk.Frame):        # settings.py:110
    def __init__(self, parent):
        super().__init__(parent)
        ...
        self.canvas = tk.Canvas(self, highlightthickness=0)     # 122 — fine
        self.scrollbar = tk.Scrollbar(self, orient="vertical",
                                      command=self.canvas.yview)  # 123 — SIGSEGV
```

Split into `yv = self.canvas.yview` / `Scrollbar(..., command=yv)`, the crash is
on the FIRST line: capturing the bound method, not passing it.

## Not yet reproduced in isolation

The same shape outside the application works — a `tk.Frame` subclass whose
`__init__` builds a Canvas into a field, reads `self.canvas.yview` into a local
and hands it to a Scrollbar, with `configparser` and the reportlab shim's rival
`Canvas` class both linked. So something else about settings.py's environment
decides it. Worth trying next:

- what `self.canvas`'s FIELD type resolves to in that class (the field pre-pass
  picks a class by name, and reportlab's `Canvas` is a rival — the
  [[decide-class-namespace-scoping]] family). A field typed as the wrong Canvas
  would make `.yview` read a method that is not there.
- whether the crash needs the ~60 later widgets in `populate_frame` to exist
  (the class is large; the repro is small).

## How to see it

```
./compiler/pascal26 -Fu<app> <app>/se3.py /tmp/se3     # se3.py: SettingsEditor(root)
DISPLAY=:99 /tmp/se3
```
with `se3.py` = `import tkinter as tk; from settings import SettingsEditor;
root = tk.Tk(); SettingsEditor(root)`.

## Gate

`make test-nilpy` plus a `.npy` reproducing whatever the isolation turns out to
need, diffed against CPython — and songformatter's window actually opening
under Xvfb.

## Reproduced in isolation, and it is not the rival Canvas (2026-07-29)

The application environment turned out to be irrelevant. No reportlab, no
configparser, no 60 widgets — the class only has to live in an **imported `.py`
module**:

```python
# m6.py — a MODULE
import tkinter as tk

class A(tk.Frame):
    def __init__(self, parent):
        super().__init__(parent)
        self.canvas = tk.Canvas(self, highlightthickness=0)
        print("field set")                       # prints
        self.canvas.create_line(0, 0, 5, 5)
        print("field METHOD CALL ok")            # prints
        yv = self.canvas.yview
        print("field CAPTURE ok")                # SIGSEGV before this
```

```python
# t6.py — the program
import tkinter as tk
from m6 import A
root = tk.Tk(); A(root); print("done")
```

The same class pasted into the MAIN file runs clean. That pair of facts settles
the two open questions in this ticket:

- a method **call** on the same field works, so `self.canvas`'s field type
  resolves correctly — the rival reportlab `Canvas`
  ([[decide-class-namespace-scoping]]) is not involved;
- the later widgets are not needed either.

## Cause

`parser.inc`, the bound-method-value arm:

```pascal
if isNilPy and (CurrentUnitIdx < 0) and (CurTok.Kind <> tkLParen) and ...
```

`CurrentUnitIdx < 0` means **the main program only**. A `.py` module compiles
with `CurrentUnitIdx >= 0`, so `obj.method` as a VALUE was not recognised there
and fell through to the call path, producing a call through a non-method — the
segfault.

## Fix

The gate becomes `((CurrentUnitIdx < 0) or PyExprMode)`. `ParsePyUnit` turns
`PyExprMode` on for a module body and Pascal RTL units never have it, so it
expresses the rule the arm actually wants: NilPy USER code, main program or
module.

Verified on the minimal module repro, on the ticket's original inline form
(`command=self.canvas.yview` passed straight to `Scrollbar`) and on a
`SettingsEditor`-shaped class; the main-file case still works.
`test/test_nilpy_bound_method_in_module.npy` (+ `test/boundfield_mod.py`) covers
capture off a field and off `self` inside a module, diffed against CPython.

Six SIBLING gates of the same shape are wrong in the same way and are filed
together as
[[bug-nilpy-object-reclamation-disabled-inside-py-modules]] — they are
self-consistent (no zero-init AND no release), so they leak rather than crash,
and they must move as a set.

## Log
- 2026-07-29 — resolved, commit HEAD.
