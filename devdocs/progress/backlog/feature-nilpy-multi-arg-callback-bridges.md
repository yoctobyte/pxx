---
summary: "nilpy runtime: pycallback_call2/3 and a multi-parameter bound-fn call, so a callable can receive more than one own argument"
type: feature
track: N
prio: 35
---

# A NilPy callable can only be handed ZERO or ONE argument from library code

- **Type:** feature (Nil-Python runtime — `compiler/builtin/pylib.pas` /
  `pyeval.pas`) — **Track N**
- **Opened:** 2026-07-31 by Track B, splitting the compiler-side half out of
  [[feature-lib-tkinter-callable-options-with-args]] per the lane rules: that
  ticket is a PCL façade feature, this is shared runtime, and Track B does not
  edit it.

## The limit

`pylib.pas` exports exactly two bridges for calling a NilPy callable from
library code:

```pascal
function pycallback_call0(const cb: Variant): Int64;
function pycallback_call1(const cb: Variant; const a0: Variant): Int64;
```

and the bound-function path underneath is the same shape —
`pyboundfn_call_ptr(objptr, const a0: Variant)` passes exactly ONE argument
(`pyeval.pas:1870`).

So a library can hand a Python callable nothing, or one value, and that is all.

## What needs it

Tk calls several options with its OWN argument lists, not with a single event:

| option | Tk calls it with |
| --- | --- |
| `-yscrollcommand` / `-xscrollcommand` | `first last` — two fractions |
| a scrollbar's `-command` | `moveto <frac>` or `scroll <n> units\|pages` |
| `-validatecommand`, `-postcommand`, trace handlers | their own argument sets |

The façade cannot express any of those as a Python callable today, and says so
loudly rather than wiring something wrong. Note the scroll pair specifically
does NOT need this — CPython's tkinter does not call back into Python for it
either, it wires Tcl straight to the other widget's subcommand, and the façade
now does the same. This is about the general shape.

Nothing outside tkinter is blocked on it today, which is why it is ranked below
the frontend bugs.

## Shape

1. `pycallback_call2` / `pycallback_call3` beside the existing pair.
2. A bound-fn / closure invoke path that accepts more than one own parameter —
   the single-argument assumption in `pyboundfn_call_ptr` is the actual
   constraint, and the two `pycallback_call*` entry points are its surface.
3. Keep the existing zero/one entry points; this widens, it does not replace.

## Gate

`make test-nilpy` green + self-host byte-identical, plus a `.npy` that hands a
def, a lambda and a bound method to a library routine which calls each with two
and with three arguments, diffed against CPython.

## Measured satisfied 2026-08-09 (by Track B, pinned v252)

The shape this ticket exists for — a callable receiving more than one of its own
arguments, including the hard case of a BOUND METHOD:

```python
class C:
    def add(self, a, b): return a + b
def call2(f): return f(4, 5)
print(call2(C().add))      # 9
```
Also plain functions (`call(cb)` with `cb(a,b)` -> 5) and multi-arg lambdas
(`lambda a, b: a*b` -> 12). Evidence only — Track N owns closing this. Found
sweeping Track B's blocked tickets;
[[feature-lib-tkinter-callable-options-with-args]] listed this as its blocker.
