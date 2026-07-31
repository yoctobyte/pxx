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

## settings.py is now the ONLY thing between us and a second module (2026-07-27)

With key_analysis.py running, `settings.py` compiles up to exactly one call:

```python
self.content_window = self.canvas.create_window((0, 0), window=self.content, anchor="nw")
```

Three separate widenings in one line, and the middle one is a design question:

1. **A tuple coordinate.** Real tkinter takes `create_window(x, y, ...)` OR
   `create_window((x, y), ...)`. The façade declares `x, y: Integer`; NilPy
   passes the tuple as a TPyList variant.
2. **`window=` is a WIDGET, not a path string.** The façade wants the Tcl path;
   the app passes the Frame object. An overload taking `window: Widget` and
   reading its `path` is the obvious fix and needs nothing new.
3. Keyword binding by name already works.

(1) is the fork worth a **Track U** decision before coding: accepting a tuple
means `lib/pcl/tkinter.pas` needs to read a TPyList out of a Variant, i.e.
`uses pylib` from a PCL unit — pulling the Python runtime into a library that
Pascal programs also use. The alternatives are a frontend rule (unpack a tuple
argument when the callee takes N ordinals — magic, and invisible at the call
site) or leaving the tuple form unsupported (which would mean an app-side edit,
against this project's mission). Recommendation: the `uses pylib` route, scoped
to a `tkinter`-only helper unit so plain Pascal PCL users never link it.

## The tuple wall is DOWN; callbacks are the next one (2026-07-27, later)

`decide-pcl-may-use-pylib` is RESOLVED by Rene: *"our PCL will be our PCL. cheats
allowed."* — a PCL façade may `uses pylib` to accept Python-shaped arguments.
`lib/pcl/tkinter.pas` now does, and `create_window((0, 0), window=<widget>,
anchor=...)` compiles.

Four frontend bugs surfaced behind that one line, all fixed:

1. The overload probe parsed `name=expr` as an expression → "undefined variable"
   for every keyword argument to an OVERLOADED method.
2. The probe used the Pascal expression chain, so a tuple argument `(0, 0)`
   stopped at the comma — it typed the argument Integer and counted two, which
   ranked an `(x, y: Integer)` overload above the tuple one.
3. `self.canvas = tk.Canvas(...)` recorded the field's class from the FIRST
   token, so the module alias `tk` resolved to tkinter's `Tk` class (Pascal is
   case-insensitive) — the field became a Tk and every use of it fell through to
   the dynamic-attribute path.
4. Field declarations were scanned in `__init__` ONLY. Real classes split their
   setup (`_build_layout`), so those fields were invisible.

### Next: CALLBACKS

`settings.py` now stops at

```python
widget.bind("<MouseWheel>", self._on_mousewheel, add="+")
```

Two things: an `add=` parameter (trivial), and a **bound method as the callback**
— the real work. `lib/pcl/tk.pas` has no command registration at all: it only
`Tcl_Eval`s strings. The shape needed is `Tcl_CreateCommand` (already the right
external to add, next to `Tcl_Eval`) registering one dispatcher that carries an
index into a table of NilPy callables, plus `command=` on Button/ttk.Button and
the `event` object (`.delta`, `.num`, `.width`, `.widget`) the handlers read.
That single feature unblocks `settings.py`, `convertrawtext.py`'s editor and the
whole GUI MVP — it is the biggest remaining item on the tkinter side.
