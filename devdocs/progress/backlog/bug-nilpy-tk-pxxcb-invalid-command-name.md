---
track: N
prio: 65
type: bug
---

# Tk: `invalid command name "pxxcb"` in a long-running app

songformatter builds its whole UI, loads a song, and then Tk pops its
background-error dialog:

```
Error: invalid command name "pxxcb"
```

`pxxcb` is the ONE Tcl command lib/pcl/tkinter.pas registers to dispatch every
Python callable. Captured with a `bgerror` handler, the failing scripts are
ordinary event bindings:

```
invalid command name "pxxcb"
    while executing
"pxxcb 248 0 0 ?? ?? 500 1026 ?? .w9.w11.w12.w14"
    (command bound to event)
```

## What is established

- The command IS registered, in the right interpreter, and
  `info commands pxxcb` answers `pxxcb` at registration time and at EVERY later
  `TkiRegisterCallbackEx` (checked with a probe on all ~490 registrations).
- Only ONE `Tcl_CreateInterp` happens (probe on `TkInit`).
- At the moment the binding fires, `info commands pxxcb` is EMPTY and
  `namespace current` is `::`. The command is gone, not shadowed.
- Registering `pxxcb` when the interpreter is created (rather than on the first
  callback) does not help — it is present after that and vanishes later.
- The failure is **heap-layout sensitive**: adding an extra `TkEval` or a
  `WriteLn` to the startup path makes it come and go. That points at a WILD
  WRITE corrupting Tcl's command hash rather than a logic error.

## Prime suspect

The callable-ABI class of bug fixed in 45fc761: an unannotated NilPy `def`
returns a Variant through a hidden destination pointer, and calling one through
an `: Int64` typedef leaves that register stale, so the callee's epilogue writes
16 bytes to a garbage address. Three such typedef sites were fixed
(`TPyCallFn0/1`, `TBF1..TBF13`, `TPyCbM0/M1/F0/F1`). If a FOURTH remains, every
callback of that shape is a 16-byte wild store — exactly the profile above.

Next step: audit every `= function(...): Int64`/`: Integer` procedural type in
compiler/builtin/** that can receive a **user** code address whose return type
is not known statically, and prove each one. The annotated-host-method families
(`TIFn*`, `TPFn*`, `TSFn*` in pyeval.pas) are keyed on a DECLARED return type
and are fine; the ones to check are the "unknown callable" paths.

Second candidate: run the app under a Tcl built with `TCL_MEM_DEBUG`, or add a
`trace add command pxxcb delete` (an earlier attempt produced no output, which
is itself consistent with corruption rather than a real delete).

## Repro

Build songformatter (`~/songformatter`) and run it under Xvfb; the dialog
appears within seconds of the first document rendering. See
[[bug-nilpy-songformatter-first-render-walls]].

## Gate

`make test-nilpy` + the songformatter window opening with NO error dialog.
