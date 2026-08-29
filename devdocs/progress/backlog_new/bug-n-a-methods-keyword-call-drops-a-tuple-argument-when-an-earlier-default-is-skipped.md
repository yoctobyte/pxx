---
track: N
prio: 55
type: bug
blocked-by: []
summary: "A NilPy keyword call to a METHOD that leaves an earlier defaulted parameter unbound rejects an object-valued (tuple/list) argument: `no overload of X matches these arguments`. The identical signature and call binds correctly through the INSTANTIATION path and through a unit-level procedure. Scalars are unaffected. Blocks tkinter's `grid(padx=(8, 6))`."
status: new
owner: ""
---

# A method's keyword call drops a tuple argument when an earlier default is skipped

- **Type:** bug — **Track N** (NilPy argument binding). Filed 2026-08-29 by
  frank-b (Track B) out of
  [[feature-lib-tkinter-grid-pad-accepts-a-two-tuple]], which is not a Track B
  defect: the tkinter facade is already complete and correct (below).
- **Measured at:** pin v393 `1d69760deabe`.

## The minimal repro — one class, two call paths

```pascal
unit vunit6;
interface
type
  TC = class
  public
    constructor Create(a: Integer = -1; const s: AnsiString = ''; const v: Variant = 0);
    procedure meth(a: Integer = -1; const s: AnsiString = ''; const v: Variant = 0);
  end;
```

```python
import 'vunit6.pas' as v6
c = v6.TC(a=0, v=(8, 6))     # OK   -> ctor tag=7
c.meth(a=0, v=(8, 6))        # FAILS -> no overload of meth matches these arguments
```

Same class, same parameter list, same call, same skipped parameter (`s`). Only
the *path* differs. That is the whole finding: **two argument-binding paths
serve one concept and only one of them fills defaults correctly for an
object-valued Variant.** The fix is presumably to make the method path do what
the instantiation path already does, rather than to patch the matcher.

## The boundary, measured

Every row is a keyword call with a `(8, 6)` argument unless stated.

| shape | result |
| --- | --- |
| unit-level procedure, gap before the Variant | **OK** |
| class instantiation `TC(a=0, v=(8,6))`, gap before | **OK** |
| **method** `c.meth(a=0, v=(8,6))`, gap before | **FAILS** |
| method, *no* gap — every parameter supplied | OK |
| method, gap, argument is a **scalar** `v=8` | OK |
| method, gap, Variant is the **first** parameter (gap after it) | OK |
| method, gap before a skipped **AnsiString** target (no Variant) | OK |
| explicit constructor call `TC.Make(a=0, v=(8,6))` | **FAILS** |
| positional first arg, `meth(0, v=(8,6))` | FAILS |
| tuple `(8,6)` vs list `[8,6]` | identical — both fail |

So all three conditions are required: a **method call**, a **defaulted
parameter left unbound before** the argument, and an **object-valued** Variant
(`pyvartag` 7). Miss any one and it binds.

Note `TC.Make(...)` — an explicit constructor call — fails while `TC(...)`
succeeds, which says the split is call-path and not constructor-vs-method.

## Where it is not

The diagnostic is raised at `compiler/pasparser_call.inc:2033`, but that is
where the failure is *reported*, not where it is caused: Pascal cannot express
a skipped middle default at all, so the gap can only have been created by
NilPy's keyword binding when it built the argument list. Start at the
NilPy side and at the difference between the two paths, not at the matcher.

## Impact

Blocks [[feature-lib-tkinter-grid-pad-accepts-a-two-tuple]], and through it
`settings.py` in [[feature-demo-songformatter-pxx-target]]. It is wider than
tkinter, though: any NilPy call into a Pascal facade whose methods take
optional Variant options — which is the shape every facade here uses — hits
this the moment an application passes a tuple without also supplying every
preceding option. `pack(padx=(8, 6))` fails for the same reason
`grid(row=0, column=0, padx=(8, 6))` does.

## What is already correct, so nobody re-does it

The tkinter facade needs no change. `padx`/`pady` on both `grid` and `pack` are
already `Variant`, and `TkiOptPad` already renders the pair as Tk's braced
list. Verified by asking **Tk** rather than our own formatter — `grid info` on
the live widgets:

```
pair  : ... -padx {8 6} -pady 2 -sticky e
scalar: ... -padx 8 -pady 2 -sticky e
pady  : ... -padx 1 -pady {3 9} -sticky e
```

reached by supplying every intermediate option to dodge this bug:
`grid(row=0, column=0, sticky="e", columnspan=1, rowspan=1, padx=(8, 6), pady=2)`
compiles and applies asymmetric padding today. That is also the **workaround**
for an application that cannot wait: name every option before the pad.

## Gate

Track N's: `make test-nilpy` green + self-host byte-identical. The repro above
must bind through the method path, and the `TC(...)` / unit-level rows must
stay green (they are the control, not the target).
