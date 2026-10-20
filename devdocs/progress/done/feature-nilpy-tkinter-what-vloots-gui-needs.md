---
track: N
prio: 30
type: feature
---

# tkinter: what Vloot's GUI needs (ttk.Style, short options, TclError, ...)

Found 2026-10-20 compiling Vloot's gui.py (~/vloot) unchanged. Each item was
a compile error or a silent difference from CPython; all now match CPython's
output (examples/tk/style_and_short_options, no_display_raises_tclerror).

- `ttk.Style()`: `theme_use` (with no name it returns the current theme),
  `theme_names`, `configure(name, background=, foreground=, font=, relief=,
  padding=, ...)`. `style=` on ttk.Frame and ttk.Label: a styled widget is a
  `ttk::` widget, which is how a ttk frame gets a colour.
- `bg=`/`fg=` beside `background=`/`foreground=` (Frame, Label, Canvas,
  Toplevel, configure/config). configure/config also take `foreground=` and
  `font=`.
- `pack(anchor=)`. `columnconfigure`/`rowconfigure` beside the `grid_` names.
- `tk.Tk()` raises TclError with Tk's reason when Tk cannot start (no
  display). TkInit's failure was ignored, so the program went down the GUI path
  and exited silently instead of falling back to the console.
- `root.after(ms, root.destroy)`: the method VALUE of `destroy` now maps to
  `destroy_`, as the call form did; it raised AttributeError at run time.

Not done: loading libtk at run time (the binary still needs libtk to start),
see feature-nilpy-tkinter-optional-libtk.
