---
track: B
prio: 45
type: feature
blocked-by: [bug-n-a-methods-keyword-call-drops-a-tuple-argument-when-an-earlier-default-is-skipped]
summary: "`widget.grid(padx=(8, 6))` — tkinter's two-tuple pad, meaning (left, right) — is rejected by the facade: `no overload of grid matches these arguments`. A scalar `padx=8` works. Real tkinter accepts both for padx and pady on grid and pack. One line of songformatter's settings.py needs it; it is the module's only remaining wall."
status: working
owner: frank-b
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


## Triage (frank-b, 2026-08-29) — NOT a Track B defect; blocked on Track N

**The facade is already complete.** `padx`/`pady` on both `grid` and `pack` are
already `Variant`, and `TkiOptPad` already renders the `(before, after)` pair as
Tk's braced list. Nothing in `lib/pcl/tkinter.pas` needed changing, and I
changed nothing.

The gate's own requirement — *"the padding actually applied asymmetrically ...
a scalar fallback that silently ignores the second element would pass a compile
check and is the wrong fix"* — is met today. Verified by asking **Tk**, not our
own formatter (`grid info` on the live widgets under xvfb):

```
pair  : ... -padx {8 6} -pady 2 -sticky e
scalar: ... -padx 8 -pady 2 -sticky e
pady  : ... -padx 1 -pady {3 9} -sticky e
```

**What actually rejects the call is a NilPy argument-binding bug**, filed as
[[bug-n-a-methods-keyword-call-drops-a-tuple-argument-when-an-earlier-default-is-skipped]].
A keyword call to a **method** that leaves an earlier defaulted parameter
unbound rejects an object-valued Variant argument. The same signature and the
same call bind correctly through the **instantiation** path and through a
unit-level procedure — same class, only the path differs:

```python
c = v6.TC(a=0, v=(8, 6))     # OK
c.meth(a=0, v=(8, 6))        # no overload of meth matches these arguments
```

Which is why the ticket's own table reads the way it does: `grid(..., padx=8)`
works because a scalar is not affected, and `grid(..., padx=(8, 6))` fails
because three options before it were left unbound. Supply them all and the
tuple form compiles and works **today**:

```python
lbl.grid(row=0, column=0, sticky="e", columnspan=1, rowspan=1, padx=(8, 6), pady=2)
```

That is the **workaround available now** for `settings.py:183` if the wasm lane
does not want to wait for the N fix — it is one line and it is not a
compiler-appeasement reshape of library code, it is an application spelling
every option it is already setting.

**Why this ticket stays open rather than being resolved:** its ask is that the
short spelling work, and it does not. But there is nothing left for Track B to
do, so it is parked on the N bug rather than held in `working/`.
