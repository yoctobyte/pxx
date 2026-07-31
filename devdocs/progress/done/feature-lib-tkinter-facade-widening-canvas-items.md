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

## RESOLVED 2026-07-31 — the "still missing" list is empty

Both gaps this ticket was filed for (StringVar.trace_add, a canvas item named by
a TAG) were already fixed when it was written. The list it left behind has since
landed too, and was re-checked one name at a time against `lib/pcl/tkinter.pas`:

`Menu`, `Text`, `Toplevel`, `PhotoImage`, `filedialog` (`askopenfilename` /
`asksaveasfilename` / `askdirectory`), `messagebox` (`showinfo` / `showwarning` /
`showerror` / `askyesno` / `askokcancel` / `askyesnocancel`), the module
constants, `event_generate`, and the geometry-manager options are all present.
ttk is not a separate unit: `ttk` resolves onto `tkinter` and the ttk widgets
sit beside the classic ones using the `ttk::` command prefix, so
`ttk.Button` / `Notebook` / `Separator` / `Frame` / `PanedWindow` all work.

The measured proof is not the census but the corpus: all five of songformatter's
modules — `settings.py`, `convertrawtext.py`, `key_analysis.py`,
`render_backend.py` and `SongFormatter.py` — now COMPILE unmodified.

The rule this ticket ends on ("every parameter Python spells with more than one
type must be a Variant") is the part worth keeping, and it held up: nothing in
this pass had to widen an `Integer` again.

## Log
- 2026-07-31 — resolved, commit bc2a960ce.
