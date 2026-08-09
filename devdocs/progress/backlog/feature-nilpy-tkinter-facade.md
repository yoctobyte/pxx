---
summary: "nilpy: tkinter-shaped façade over lib/pcl/tk.pas — widget objects, kwargs, command callbacks"
type: feature
track: N
prio: 50
---

# nilpy: a tkinter façade (object API + callbacks)

- **Type:** feature (Nil-Python frontend / stdlib surface) — **Track N**
  (the Tk binding underneath is Track B and already landed)
- **Status:** backlog
- **Opened:** 2026-07-26 — needed now that the songformatter target is scoped to
  its GUI ([[feature-demo-songformatter-pxx-target]]).

## What exists vs what real code writes

`feature-nilpy-tk-binding` (done) gives `import tk`: `TkInit`/`TkEval`/`TkMainLoop`
over Tcl/Tk command strings, with a POLL event model (a widget sets a Tcl variable;
the program polls it). Deliberately thin, and proven.

Real tkinter code — songformatter, and every Python GUI — instead writes widget
OBJECTS with keyword options and function callbacks:

```python
import tkinter as tk
from tkinter import ttk
root = tk.Tk()
cv = tk.Canvas(root, background="white", highlightthickness=0)
cv.pack(side="left", fill="both", expand=True)
cv.create_text(x, y, text=s, anchor="sw", fill="#000000", font=("Helvetica", -17))
ttk.Button(panel, text="Preview PDF", command=preview_pdf).pack(side=tk.LEFT)
cv.bind("<Configure>", on_resize)
root.after(120, redraw)
```

## Shape

A façade written in Nil-Python (or a nilpy-visible module) that maps widget objects
and their options onto `TkEval` command strings — the same trick CPython's tkinter
plays. Needs, in order:

1. `**kwargs` on the callee side ([[feature-nilpy-star-args-kwargs]]) — tkinter's
   entire API is keyword options.
2. A callback story. The poll model can carry `command=` if the façade registers
   the function in a dispatch table keyed by a generated Tcl variable and drains
   them inside the mainloop — no C trampoline, staying as thin as the existing
   binding. `bind()` and `after()` want the same mechanism. Calling a function
   stored in a table depends on [[feature-nilpy-lambda]] /
   [[feature-nilpy-bound-method-value]] working as values.
3. The widget/option subset songformatter uses: `Tk`, `Toplevel`, `Frame`,
   `Canvas` (create_text/line/oval/rectangle/image, bbox, coords, delete,
   scrollregion, xview/yview), `Scrollbar`, `Text`, `Menu`, `PanedWindow`,
   `Notebook`, `Button`, `PhotoImage`, plus `pack`/`place` geometry and
   `tkinter.font` metrics (the preview needs `descent` and `measure`).

## Note

The parallel-canvas preview means the GUI path needs no PDF renderer — the same
drawing calls feed screen and PDF (see the umbrella ticket's scope section). But it
does mean the Canvas surface above is load-bearing, not decorative.

## Gate

`make test-nilpy` green with a `.npy` GUI case under xvfb (widget with a
`command=` callback that fires, and a Canvas drawing), + `--tier quick` +
self-host byte-identical.

## Unblocked 2026-08-09 (Track B): the blocker is satisfied in practice

Swept as part of checking whether Track B's blocked tickets were still really
blocked — the pattern this session kept hitting is that they were not. The
capability this ticket waited on was MEASURED working on the current pin (v252);
the evidence is recorded on the blocker itself, which Track N still owns
formally closing.

`blocked-by` removed here so the ticket stops hiding from `progress.sh ready`.
