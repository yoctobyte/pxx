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

## ROOT CAUSE FOUND (2026-07-29)

A **nested `def` inside a method**, taken as a VALUE, resolved to the bodyless
shell the pre-pass registers under the UNqualified name — the real routine is
registered as `Class.method.name`. `@shell` then linked as `entry + BodyAddr`
with `BodyAddr = -1`, i.e. one byte below the entry point (0x4000E7 here): a
plausible-looking pointer that crashes the first time the callback fires.

songformatter hits it with `cv.bind("<Configure>", on_resize)` where `on_resize`
is nested inside `FormatText.convert_text`. The wild jump is what leaves Tcl's
command table unusable, which is why the SYMPTOM was `invalid command name
"pxxcb"` on every later event, hundreds of widgets away from the cause — and
why adding a single extra `TkEval` at startup flipped the app between "runs with
an error dialog" and "SIGILL at startup": both are the same corruption seen
through different heap layouts.

Two fixes landed:
- `PyMakeFuncValue` looks the qualified name up first (`PyNestPrefix + '.' + n`).
- The ELF writer now REFUSES `@proc` when `BodyAddr < 0` and names the routine,
  so this class of bug is a link-time diagnostic instead of silent corruption.

With those in, songformatter gets further: `on_resize`/`draw` now really run,
and the crash moves INSIDE the preview redraw — a 1-argument dynamic call
(`AN_CALL_IND`, `pyvarobj` unbox then `call *r11`) whose callee variant is NIL.
Tracked as the next wall on
[[bug-nilpy-songformatter-first-render-walls]]; a nil guard on the dynamic-call
path would turn that one into a diagnostic too.

## Earlier suspect (kept for the record)

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

## 2026-07-30: VERIFIED GONE

Rebuilt songformatter and drove it under Xvfb with the exact event classes the
failing scripts came from — window resizes (six, each a `<Configure>` on the
canvas), mouse-wheel scrolling in both the editor and the preview pane, and tab
switches. The app restores its three-document session, renders the song, the
preview and the key analysis (`Key: F | Alt: C dorian | Agree: 1/7`), and
survives all of it with an EMPTY stderr: no `invalid command name "pxxcb"`, no
background-error dialog. Screenshot-verified.

The two fixes already recorded above are what did it — the qualified lookup in
`PyMakeFuncValue` and the ELF writer refusing `@proc` on a bodyless routine. The
`@shell` wild jump was the corruption; with it gone Tcl's command table survives.
Confirmed against a compiler built from the commit BEFORE this session's changes
as well, so nothing landed today is load-bearing for it.

The "audit every `: Int64` callable typedef" step recorded below was NOT needed
for this symptom. It stays worth doing on its own merits — and one more member
of exactly that family did turn up today, in a different place: a lifted lambda
never stashed its hidden Variant-result pointer, so its epilogue copied 16 bytes
to stale stack garbage (fixed under
[[bug-nilpy-nested-def-capture-sets-are-not-final]]). Same profile, same class,
different site.

## Repro

Build songformatter (`~/songformatter`) and run it under Xvfb; the dialog
appears within seconds of the first document rendering. See
[[bug-nilpy-songformatter-first-render-walls]].

## Gate

`make test-nilpy` + the songformatter window opening with NO error dialog.
