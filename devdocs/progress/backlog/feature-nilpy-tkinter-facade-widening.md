---
summary: "tkinter façade: the surface a real GUI app needs (callables, ttk, Menu, Text, tuple coords)"
type: feature
track: B
prio: 60
---

# tkinter façade: widen it to what a real application uses

- **Type:** feature (library — **Track B**, file-owned; build with `$(PXX_STABLE)`)
- **Opened:** 2026-07-27, walking songformatter's GUI modules
  ([[feature-demo-songformatter-pxx-target]]). The façade itself landed as
  [[feature-nilpy-tkinter-facade]]; this is the widening.

## Where it stands

`lib/pcl/tkinter.pas` is 9 classes and ~72 members: Widget, Frame, Canvas,
Scrollbar, Label, Entry, Checkbutton, StringVar, BooleanVar, plus `Tk`. That was
enough for a demo. songformatter's three GUI modules need substantially more, and
the gaps are now measured rather than guessed.

## What is missing, in the order the app hits it

1. **Callable options.** `command=self.refresh`, `bind("<Configure>", handler)`,
   `configure(yscrollcommand=self.scrollbar.set)`, and `command=lambda event: …`.
   Every option today is a STRING (a Tcl script). This is the big one: it needs
   the NilPy function-value path (Callable parameters, which the frontend already
   has for defs) wired through the façade, plus a Tcl-side trampoline that calls
   back into the compiled program.
2. **Tuple coordinates.** `create_window((0, 0), window=…, anchor="nw")` passes a
   TUPLE where the façade takes x, y. A tuple is a TPyList, so accepting one
   means the façade depends on pylib — which is a decision, not an oversight: it
   would make lib/pcl/tkinter.pas nilpy-only rather than dual-use. Decide before
   writing it.
3. **The widget classes still absent:** `Menu` (32 `add_command` calls),
   `Toplevel`, `Text`, `PhotoImage`, and the ttk family — `ttk.Button` (13),
   `ttk.Notebook`, `ttk.Separator`, `ttk.Frame`, `ttk.Label`, `ttk.PanedWindow`.
4. **The module-level constants** — `tk.LEFT` (19 uses), `tk.END` (15), `tk.BOTH`,
   `tk.X`, `tk.Y`, `tk.TOP`, `tk.VERTICAL`, `tk.WORD` — and `tk.TclError`.
5. **`filedialog` and `messagebox`** (both imported by two modules).
6. **Geometry/selection methods** on Widget: `grid` variants, `event_generate`,
   `focus_set`, `winfo_*`, `tabs`/`select`/`index` for Notebook.

## Naming rule (learned the hard way)

A façade class must carry the name the application writes. `Label_` was a
symmetry habit and it cost the mission its whole point — an app writes
`tk.Label(...)` and must not have to write anything else. Same for `Tk`. When a
Python name genuinely collides with a Pascal keyword, the collision (not the
convention) is what justifies a different spelling, and it should be documented
at the declaration.

## Gate

`make lib-test` / the façade example compiles, and the widened surface is
exercised from a `.npy` under Xvfb (see `docs/developer/gui-testing.md` — never
grab the real display).
