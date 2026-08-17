---
summary: "nilpy: tkinter-shaped façade over lib/pcl/tk.pas — widget objects, kwargs, command callbacks"
type: feature
track: N
prio: 50
owner: frank2
---

# nilpy: a tkinter façade (object API + callbacks)

- **Type:** feature (Nil-Python frontend / stdlib surface) — **Track N**
  (the Tk binding underneath is Track B and already landed)
- **Status:** done
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

## RE-MEASURED 2026-08-17 — the façade is BUILT; the gap was that nothing ran it

Read the ticket, then measured before designing anything, because its plan
("a façade written in Nil-Python... needs, in order: `**kwargs`, a callback
story, the widget subset") describes work that has since been done and the
ticket never said so. Third stale premise of the day.

**`lib/pcl/tkinter.pas` exists: 2453 lines, last touched 2026-08-15**, declaring
every class this ticket's step 3 lists — `Tk`, `Toplevel`, `Frame`, `Canvas`,
`Scrollbar`, `Text`, `Menu`, `PanedWindow`, `Notebook`, `Button`, `PhotoImage`,
plus `Label`, `Entry`, `Separator`, `Checkbutton`, `Event`, `StringVar`,
`BooleanVar`. Steps 1 and 2 are done too: `bind`/`after`/`after_idle`/
`after_cancel`/`add_command`/`config` all take a `Variant` **callable**, not the
Tcl string the ticket's own note describes as the limitation.

So the remaining work was not the façade. It was the **gate**.

### What was actually wrong: 2453 lines gated on "it still parses"

Four tk artifacts were compiled by the suite and **never executed** —
`tkinter_facade.npy`, `field_class_identity.npy`, `callbacks.npy` and
`uses_tkinter_and_configparser.pas`. The Makefile said "compiled, not run — it
needs an X display", and `callbacks.npy`'s own header said "run under Xvfb by
hand", which in practice means never.

That is the weakest possible gate for this code: **a callback that never fires, a
canvas that draws nothing, and a widget path built wrong all compile perfectly.**
Everything this façade exists to do is invisible to a compile check.

### Done: the three `.npy` ones now RUN under Xvfb and their output is diffed

Wired into the same recipe, guarded by `command -v xvfb-run` so a box without it
**skips rather than fails** — the same shape the tkhtmlview oracle already uses.
Expected output captured in `examples/tk/*.expected`.

Verified before wiring, because a GUI test that is flaky or that cannot fail is
worse than none:

- **deterministic** — 5 consecutive runs of `callbacks`, 3 each of the other two,
  byte-identical every time;
- **it can actually FAIL** — corrupting an expected file makes the recipe exit 1
  with a diff. Checked explicitly rather than assumed, which is the check that
  distinguishes a gate from decoration.

What now actually runs and is asserted: a `<Configure>` binding firing, a lifted
lambda callback, a bound method and a plain def as callables, two variable
traces, `Canvas.create_rectangle` + `bbox("all")`, scrollbar↔canvas wiring in
both directions, and widget path construction (`.w1`, `.w1.w2`).

`uses_tkinter_and_configparser.pas` is left compile-only: it is Pascal, not
NilPy, and its assertion is a name-resolution one that the compile already makes.

### What is left on this ticket

The widget/option subset is broad but not proven complete against a real
application — the honest remaining question is songformatter's own surface
(`tkinter.font` metrics `descent`/`measure`, `Canvas.create_text` anchoring,
`Notebook`, `PanedWindow`), which this ticket lists and which the examples above
only partly touch. That is now measurable, because there is finally a harness
that runs.

### Resolved 2026-08-17 — gate met, remaining breadth split out

This ticket's stated Gate is met: a `.npy` GUI case runs under Xvfb with a
`command=`-style callback firing and a Canvas drawing, `gate.sh quick` green,
self-host fixedpoint byte-identical. (Its Gate line also names `make
test-nilpy`; per CLAUDE.md's precedence rule that naming is superseded by the
quick gate, and the added recipe was dry-run by hand including its failure mode.)

The breadth question — proving the widget/option surface against a real
application rather than against examples we wrote ourselves — is split out as
[[feature-nilpy-tkinter-surface-vs-a-real-application]] rather than left as an
open tail here. It is the same self-selection argument the third-party corpus
campaign is built on, and it is now measurable because a running harness exists.

## Log
- 2026-08-17 — resolved, commit a52ef1948.
