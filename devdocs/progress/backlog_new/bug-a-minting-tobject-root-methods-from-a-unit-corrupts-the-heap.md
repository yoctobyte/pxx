---
slug: bug-a-minting-tobject-root-methods-from-a-unit-corrupts-the-heap
title: "Pulling `builtin` + the TObject root methods from inside a unit pre-scan crashes a NilPy program"
track: A
prio: 45
type: bug
blocked-by: []
status: backlog_new
owner: ""
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
