---
track: N
prio: 65
type: bug
---

# NilPy object reclamation is switched off inside an imported `.py` module

Found 2026-07-29 while fixing
[[bug-nilpy-settings-editor-segfaults-on-bound-method-field]], whose whole cause
was one gate of this shape being wrong.

Seven NilPy-only rules are gated on `isNilPy and (CurrentUnitIdx < 0)`:

```
compiler/symtab.inc:5703   scope-exit PXXObjRelease for a class local
compiler/parser.inc:7810   zero-init of a NilPy class local
compiler/ir.inc:1979       (argument path)
compiler/ir.inc:6188       release-on-rebind, scalar over a class binding
compiler/ir.inc:6207       retain/release on a class-to-class rebind
compiler/ir.inc:6255       field-store ARC
compiler/ir.inc:6825       (call-result path)
```

`CurrentUnitIdx < 0` means **the main program only**. A class defined in an
imported `.py` module is NilPy user code just as much, but compiles with
`CurrentUnitIdx >= 0`, so none of these fire for it.

The set is at least self-consistent — no zero-init AND no release, so nothing
reads stale stack bytes — which is why this is a leak and not a crash: objects
created by a module's classes are never reclaimed, while the identical class in
the main file is. songformatter is exactly this shape (every class lives in an
imported module), so it gets no reclamation at all.

## Why it is filed rather than fixed

Flipping all seven to `((CurrentUnitIdx < 0) or PyExprMode)` — the discriminator
that fixed the bound-method gate, since `ParsePyUnit` sets `PyExprMode` for a
module body and Pascal RTL units never have it — is a one-line change each, but
it turns reclamation ON for a body of code that has never run with it. That
wants its own measurement (RSS slope on a module-heavy program, per
[[project_leak_vs_arena_artifact_diagnosis]]), not a drive-by edit at the end of
an unrelated fix.

They must also move TOGETHER: zero-init without release leaks, release without
zero-init frees garbage.

## Gate

`make test-nilpy` + a module-heavy `.npy` measured for RSS slope before and
after, plus the existing reclamation tests.
