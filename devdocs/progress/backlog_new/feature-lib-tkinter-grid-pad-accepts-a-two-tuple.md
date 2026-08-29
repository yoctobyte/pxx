---
track: B
prio: 45
type: feature
blocked-by: []
summary: "`widget.grid(padx=(8, 6))` — tkinter's two-tuple pad, meaning (left, right) — is rejected by the facade: `no overload of grid matches these arguments`. A scalar `padx=8` works. Real tkinter accepts both for padx and pady on grid and pack. One line of songformatter's settings.py needs it; it is the module's only remaining wall."
status: new
owner: ""
---

# tkinter facade: `grid(padx=(8, 6))` — the two-tuple pad

- **Type:** feature (library surface, tkinter facade) — **Track B**.
- **Filed:** 2026-08-29 by the wasm lane against pin v392 (`60b060bb54a8`).

## Repro

```python
import tkinter as tk
root = tk.Tk()
lbl = tk.Label(root, text="x")
lbl.grid(row=0, column=0, padx=(8, 6), pady=2)
```
```
pascal26:4: error: no overload of grid matches these arguments
```

| call | result |
| --- | --- |
| `grid(row=0, column=0)` | ok |
| `grid(..., padx=8, pady=2)` | ok |
| `grid(..., sticky="e", padx=8, pady=2)` | ok |
| `grid(..., padx=(8, 6), pady=2)` | **fails** |

So the whole option surface is fine and it is specifically the tuple form.

## What tkinter means by it

`padx`/`pady` take either a scalar (that much padding on both sides) or a
2-sequence `(before, after)` — left/right for `padx`, top/bottom for `pady`. Tcl
receives it as a two-element list, so the facade needs to emit `-padx {8 6}`
rather than a single number. `pack` takes the same forms and should get the same
treatment in the same pass; `place` does not have these options.

Note the brace-quoting half is already understood here: a multi-word option
value reaching Tk unbraced was the `-scrollregion 0 0 500 1026` bug fixed during
pass seven of [[feature-demo-songformatter-pxx-target]], where three of the four
numbers arrived as stray arguments. Same shape, so the same escaping applies.

## Why it is worth doing now

`settings.py:183` is the only remaining wall in that module —
`label.grid(row=row, column=0, sticky="e", padx=(8, 6), pady=2)` — and
settings.py otherwise compiles and runs, building all 60 of its widgets. This is
the last thing between it and a clean build.

## Gate

Track B's: `make lib-test` / `make demos` green, built with `$(PXX_STABLE)`
(never rebuild the compiler), plus the repro above compiling and the padding
actually applied asymmetrically on screen — a scalar fallback that silently
ignores the second element would pass a compile check and is the wrong fix.
