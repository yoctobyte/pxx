---
slug: bug-a-minting-tobject-root-methods-from-a-unit-corrupts-the-heap
title: "Pulling `builtin` + the TObject root methods from inside a unit pre-scan crashes a NilPy program"
track: A
prio: 45
type: bug
blocked-by: []
status: done
owner: claude-A
created: 2026-08-25
summary: "When the per-unit pre-scan fired ParseUsesUnitAmbient('builtin') + EnsureTObjectRootMethods while parsing lib/rtl/json.pas, every NilPy program importing json broke: test_nilpy_json_reparse_heap SEGFAULTED and test_nilpy_json_module silently dropped an output line. The trigger was a false positive and has been fixed; that MINTING those rows from a unit can corrupt a program at all has not been."
---

# What happened

`f064c591b` added a per-unit pre-scan that mints TObject's root methods when a
unit mentions a dot-preceded `Equals` / `GetHashCode` / `ToString`:

```pascal
if unitNeedsRootMeth and (not NoDefaultRtl) and (not TargetIsEspClass) then
begin
  ParseUsesUnitAmbient('builtin');
  EnsureTObjectRootMethods;
end;
```

`lib/rtl/json.pas` line 307 is `function TJSONValue.ToString(pretty: Boolean)`
— a qualified IMPLEMENTATION HEADER, which is dot-preceded like a call. So the
scan fired on every NilPy program that imports `json`, and two of them broke:

| test | before | after |
| --- | --- | --- |
| `test_nilpy_json_reparse_heap.npy` | prints 4 lines | **SIGSEGV, no output** |
| `test_nilpy_json_module.npy` | 14 lines | 13 — `song 120 b 3` missing |

The trigger is fixed (`bfb7b4c59`'s successor): the scan now walks back past
`<TypeName> .` and refuses `function` / `procedure`, so a definition no longer
reads as a use. `test_tobject_root_methods_inside_a_unit` still passes, because
its unit has a real `L.Equals(R)` CALL as well as the headers — which is the
right discrimination.

# What is NOT fixed, and why this ticket exists

**Minting those rows from a unit should not be able to break the program.** It
did, and worse than loudly: a segfault in one test and a *silently missing line*
in the other. A unit that legitimately calls `.ToString` on a TObject and is
reachable from a NilPy program would presumably still hit it. That path is now
unreachable via json.pas, so nothing gates it.

Not measured, and this is the first thing to establish: **which half does it** —
`ParseUsesUnitAmbient('builtin')` pulling a unit mid-parse of another unit, or
`EnsureTObjectRootMethods` adding VMT rows to TObject after some class layouts
are already fixed. Split the two and run
`test_nilpy_json_reparse_heap.npy` against each; do not write a cause into this
ticket until one of them reproduces it alone. (The reparse test's own header says
it exists because a double-finalize once released the caller's string — so a VMT
row count changing under a class whose finalizer slot is already resolved is a
plausible shape, but plausible is exactly what this repo's playbook says not to
bank.)

# Repro

Revert the `function`/`procedure` guard in `pasparser_proc.inc`'s
`unitNeedsRootMeth` scan, rebuild, then:

```
./compiler/pascal26 test/test_nilpy_json_reparse_heap.npy /tmp/x && /tmp/x
```

SIGSEGV, exit 139. CPython prints `1 / 1 / {"a": 1} / x`.

# Related

The PROGRAM-level trigger this was modelled on has the same
definition-reads-as-a-use false positive (a program that defines a class with a
`ToString` method drags in the root-method surface). It does not crash there, so
it is a size/waste issue rather than a correctness one — but it is the same
missing check, and worth fixing in the same edit as this.


## MEASURED and NARROWED 2026-08-25 — it is the `Destroy` row, not the `builtin` pull

Both halves were split and run separately, with the false trigger deliberately
re-enabled so `lib/rtl/json.pas` fired the scan:

| unit pre-scan does | `test_nilpy_json_module` | `test_nilpy_json_reparse_heap` |
| --- | --- | --- |
| `ParseUsesUnitAmbient('builtin')` + `EnsureTObjectRootMethods` | drops a line | **SIGSEGV** |
| `ParseUsesUnitAmbient('builtin')` only | pass | pass |
| both, with ONLY the `Destroy` registration disabled | pass | pass |

So pulling `builtin` mid-unit is harmless, and minting `Equals` /
`GetHashCode` / `ToString` is harmless. **Minting a `Destroy` ROW on TObject
from a unit pre-scan is what corrupts the program.**

That is consistent with WHEN each caller runs — the program-level caller runs at
the END of pass 1, with every class already declared, while the unit pre-scan
runs before its own unit's classes are parsed — but the mechanism by which an
early `Destroy` row turns into a segfault is **not** established, and is
deliberately not written here as a guess. (The obvious suspect, the inline
`PXXClassFinalize` double-finalize, is explicitly guarded by `isNilPy` in
`ir.inc`, so the obvious story does not survive a read.)

## Fixed by removing the only way to reach it

`EnsureTObjectRootMethods` is split: `EnsureTObjectRootMethodsEx(withDestroy)`
carries the body, the old name calls it with `True`, and the unit pre-scan calls
it with `False`. Destroy has nothing to do with that scan's trigger — a
dot-preceded `Equals`/`GetHashCode`/`ToString` — and the routine's own comment
already said Destroy is registered separately because it comes from a different
unit. The program path still mints it at end of pass 1, after every class.

Verified the fix protects the ACTUAL hazardous path, not just the current one:
with the false trigger re-enabled so json.pas fires the scan again, both `.npy`
tests pass. `test_tobject_root_methods_inside_a_unit` (a unit with a real
`L.Equals(R)` call) and `test_pascal_free_through_base_destroy` (the ticket that
put Destroy in this routine) are both unchanged.

## Still open, and why this stays worth a ticket

Nothing explains the crash. It is now unreachable rather than understood, so a
future caller that mints a root method early can rediscover it — and the failure
mode is a segfault in one program and a *silently missing output line* in
another, which is the expensive kind. Re-file or reopen if a third caller
appears. Reproduce by making the unit pre-scan call
`EnsureTObjectRootMethodsEx(True)` and reverting the `function`/`procedure`
guard beside it.

Gate: `make compiler/pascal26` converged, `tools/gate.sh quick` GREEN.

## Log
- 2026-08-25 — resolved, commit f1cea0d74.
