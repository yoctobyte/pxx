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
