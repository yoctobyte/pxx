---
summary: "nilpy/PCL: tkinter callbacks — a bound method as command=/bind(), via Tcl_CreateCommand"
type: feature
track: B
prio: 65
---

# Callable options for the tkinter façade — LANDED 2026-07-28

Done: `Tcl_CreateCommand` in `lib/pcl/tk.pas`, one `pxxcb` dispatcher, a
callback registry and an `Event` object in `tkinter.pas`, and three callable
shapes reaching Tk — a BOUND METHOD (`self._on_wheel`), a plain def name, and a
`lambda`. `bind(..., add="+")`, `Checkbutton(command=...)` and
`BooleanVar.trace_add` all route through it. Example: `examples/tk/callbacks.npy`
(compiled by the suite, run under Xvfb).

What it needed on the compiler side: `pycallback_call0/1` in pylib (call a
function value from library code), a bare def NAME as a value
(`PyMakeFuncValue`), keyword arguments on overloaded and field-receiver method
calls, and a real `super().__init__`.

REMAINING for songformatter: a lambda that calls a METHOD on a captured object —
[[feature-nilpy-lambda-compiled-closure]].


- **Type:** feature (PCL façade + a little frontend) — **Track B**
- **Opened:** 2026-07-27, the wall `settings.py` now stops at.

## What blocks

```python
widget.bind("<MouseWheel>", self._on_mousewheel, add="+")
button = tk.Button(parent, text="OK", command=self.save)
```

The façade takes a Tcl SCRIPT STRING for both. Real applications pass a callable,
and it is usually a BOUND METHOD, so the callback carries a receiver.

## Shape

`lib/pcl/tk.pas` today only `Tcl_Eval`s strings — no command registration. Add:

1. `Tcl_CreateCommand` (an `external 'libtcl8.6.so.0'` next to `Tcl_Eval`) and
   ONE dispatcher registered as `pxxcb`, whose client data is an index into a
   table of registered callables.
2. A registry in `tkinter.pas`: `function TkiRegisterCallback(cb): Integer`,
   returning the index; the Tcl side then gets `{pxxcb 7 %d %x %y}`.
3. The callable itself. NilPy function values already have ONE ABI
   ([[bug-nilpy-callable-return-abi-mismatch]]) — variant parameters, variant
   result — which is exactly what a generic dispatcher needs. A BOUND method
   additionally needs its receiver; `PyMakeBoundMethod` already exists for the
   variant path, so check whether its value survives into a `Callable[...]` slot.
4. The `event` object handlers read: `.delta`, `.num`, `.width`, `.height`,
   `.x`, `.y`, `.widget`. Tk substitutes those as `%`-codes in the script, so the
   dispatcher can fill a small event record from its arguments.
5. `add="+"` on `bind` (append rather than replace) — one extra parameter.

## Why it matters

It is the single biggest remaining item for the GUI MVP: `settings.py`,
`convertrawtext.py`'s editor and `SongFormatter.py` all stop here.
Part of [[feature-nilpy-tkinter-facade-widening]], filed separately because it is
a mechanism, not more surface.

## Gate

`make test-nilpy` (compile-only for the façade, as the other tkinter tests are),
an `examples/tk/` demo that runs under Xvfb and prints what the callback saw,
and `settings.py` getting past line 144.
