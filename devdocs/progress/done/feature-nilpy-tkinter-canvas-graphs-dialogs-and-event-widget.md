---
track: N
prio: 30
type: feature
---

# tkinter: what a Resources-style monitor needs (Vloot's GUI)

Asked 2026-10-20 by neo-73, before writing Vloot's GUI in the style of GNOME's
"Resources" app. Each gap was checked with a probe program against python3
under Xvfb. All of them were missing or failed to compile.

**Added (lib/pcl/tkinter.pas, lib/pcl/mimic_tkinter_font.pas):**
- **Canvas:**
  - `create_polygon`.
  - Coordinates on every `create_*` as four numbers, a flat list or a list of
    `(x, y)` pairs.
  - `tags=` on every `create_*`.
  - `coords()` both gets and sets (at most 4 numbers, or a list of any
    length).
  - `itemconfig` (an alias of `itemconfigure`), which also gains
    `outline`/`font`/`anchor` and a float `width`.
  - `itemcget`, `find_all`/`find_withtag` (which return tuples),
    `tag_raise`/`tag_lower`, `yview_moveto`/`xview_moveto`.
  - `delete` by tag, which now has tags to name.
- **Every widget:**
  - `bind_all`/`unbind_all`, `event_generate(seq, x=, y=)` (it was Text-only),
    `configure(cursor=)`.
  - `geometry`/`minsize`/`maxsize`/`resizable` on the root as well as on a
    Toplevel; `geometry` moved there from Toplevel.
  - `wait_window`.
- **Frame and Label:** `cursor=`.
- **`event.widget`** is the widget the binding was made on, so
  `e.widget.configure(...)` and `e.widget is tile` work. It used to be the Tcl
  path string. It is None for `bind_all`.
- **`ttk.Style.map(name, background=[(state..., value)], ...)`.**
- **`tkinter.font.Font(family=, size=, weight=, slant=)`** or `Font(font=spec)`,
  with `measure`, `metrics` and `actual`. A Font works as any widget's `font=`.
- A font tuple's family is now braced, so `("DejaVu Sans", 11)` is one family.

**Not done, design around it:** `createfilehandler`, and `coords` with more
than four positional numbers.

Test: `examples/tk/canvas_items_dialog_and_events.npy` (python3's output, Xvfb).
