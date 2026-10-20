---
track: N
prio: 20
type: feature
---

# tkinter for Vloot's sidebar, cards and hover rows

What Vloot's GUI needed beyond the canvas graphs
(feature-nilpy-tkinter-canvas-graphs-dialogs-and-event-widget), found
building it natively on 2026-10-20:

- `tk.Tk(className="vloot")`: TkSetClassName sets Tcl's argv0 (first
  letter lower-cased, as CPython's _tkinter does) before Tk_Init, so
  `winfo_class()` is `Vloot` (WM_CLASS).
- `uniform=` on grid_columnconfigure / grid_rowconfigure / columnconfigure /
  rowconfigure.
- Widget: pack_propagate, grid_propagate, pack_forget, grid_forget,
  iconphoto(default, image), winfo_class, winfo_ismapped.
- Frame: highlightbackground, highlightcolor, borderwidth, relief.
- Label: justify, padx, pady, wraplength, width, borderwidth, relief (ttk
  labels: justify, wraplength, width).
- Entry: font, background, foreground, bg, fg.
- PhotoImage: width=/height=; `data` is used only when it is a str/bytes.
- `w.bind(seq, lambda e: ...)` through an untyped `w`:
  bug-nilpy-variant-bind-with-a-lambda-picks-the-string-overload.

Vloot's GUI (`--threadsafe vloot_gui.py`) now builds and draws the same window
as CPython under Xvfb (screenshots compared; only the live figures differ).

Test: examples/tk/sidebar_cards_and_hover_rows (python3's output, under Xvfb).
