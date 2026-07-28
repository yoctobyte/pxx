---
track: B
prio: 40
type: feature
---

# tkinter façade: item specs, StringVar traces, and what settings.py still needs

Two gaps the façade hit the moment songformatter's `settings.py` RAN (both
fixed, recorded here for the next pass over the surface):

- **`StringVar` had no `trace_add`.** `BooleanVar` did. An `Entry`'s
  `textvariable` is a StringVar, so the trace an editable field uses was the
  missing one — and an unresolved method compiles clean and jumps to 0
  ([[bug-nilpy-unknown-method-segfaults]]), so it was a segfault, not a
  diagnostic.
- **A canvas item is named by its id OR by a TAG.** `bbox`/`itemconfigure` took
  an `Integer`, so `canvas.bbox("all")` — the commonest call in the widget —
  raised `TypeError: expected a number, got str` from inside the callback.
  `TkiItemSpec` now takes either.

## Still missing for songformatter

`Menu`, `ttk.Notebook`/`Button`/`Separator`/`Frame`/`PanedWindow`, `Text`,
`Toplevel`, `PhotoImage`, `filedialog`, `messagebox`, the constants
(`LEFT`/`END`/`BOTH`/…), `event_generate`, and the remaining geometry-manager
options. See [[feature-nilpy-tkinter-facade-widening]].

## Rule the two gaps illustrate

Every parameter of this façade that Python spells with more than one type must
be a `Variant` (an item id or a tag, a number or a pair, a name or a font
tuple). An `Integer` parameter is a bet that the application never writes the
other spelling, and settings.py lost that bet twice in one file.
