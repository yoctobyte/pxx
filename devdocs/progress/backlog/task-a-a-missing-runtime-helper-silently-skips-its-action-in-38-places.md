---
slug: task-a-a-missing-runtime-helper-silently-skips-its-action-in-38-places
track: A
type: task
prio: 20
status: open
found: 2026-09-29
found-by: frankH (after frankd-90 caught the SetLength clamp skipping itself), asked by frankuser
owner: ""
blocked-by: []
summary: "38 sites in the compiler look up a runtime helper with FindProc and, when it isn't there, exit silently without the action the helper provides. That is how the first SetLength clamp fix (5ebf185c24) failed: it called builtin's PXXShortLenClamp, builtin is loaded into a no-uses program only on a trigger name, and a missing helper meant no clamp and a segfault, while the fixtures passed because they called HexStr. The clamp is now inline and needs no helper. The other 37 sites are unaudited: some are legitimately optional (a NilPy runtime routine in a Pascal program, or --no-default-rtl in the compiler's own build), and some guard a correctness or memory-safety action. Blanket conversion to a compile error would break legitimate compiles, so each site needs a probe: can a default-profile program reach it with the helper absent?"
---

# A missing runtime helper silently skips its action in 38 places

`grep -n -A1 "FindProc('...')" compiler/*.inc`, filtered to a following
`if ... < 0 then Exit` (or `begin Result := -1; Exit; end`), gives 38 sites
on 2026-09-29: 18 on the Pascal side and 20 in pyparser.inc.

## How it bit

5ebf185c24 clamped a variable SetLength count through builtin's
PXXShortLenClamp and skipped the clamp when FindProc returned -1. A program
with no uses clause loads builtin only when a pre-scan trigger name appears
(pasparser_prog.inc). frankd-90's `var t: string[10]; n := 50; SetLength(t,
n)` + fill segfaulted on the tip; adding `HexStr` anywhere made it pass. Both
fixtures called HexStr, so they were green for the wrong reason. Fixed inline
(no helper) with test_setlength_clamps_with_no_builtin_in_the_program, whose
negative control fails on the pushed tip e0b85a7460.

## Triage of the Pascal-side sites (unprobed)

Guards a CORRECTNESS or SAFETY action. Probe these first:

| site | helper | skipped action if absent |
| --- | --- | --- |
| ir.inc IRWrapNilChk | PXXNilRef | the nil check itself |
| ir.inc IREmitCaughtExcFree | PXXObjFree | freeing a caught exception object (leak) |
| pasparser_call.inc EmitMainBodyIntfTempRelease | PXXIntfRelease | releasing main-body interface temps (leak) |
| ir.inc IRStrUniqueForByRefElem | PXXStrUnique | copy-on-write before a var-param element write (aliasing) |
| ir.inc IRClassMatchRuntime | __pxxInheritsFrom | runtime class match (what does the caller fall back to?) |
| pasparser_stmt.inc GenMakeDestroyCall | __pxxTObjectDestroy | the destructor on Free (MEASURED OK: builtinheap is pulled in for classes; a no-uses program's `TObject(p).Free` runs the override) |

Probably legitimately optional (feature absent, and so is its use):
PromoWidenToDouble (PXXPromoToDouble, "promocore not loaded"),
IRDropManagedResult and SLReleaseLocalsAtDone (PXXObjRelease, NilPy object
model), IRPyVarEqTry (pyvar_eqv), GenMakeClassRefOp's __pxxClassName family,
GenMakeGetInterfaceCall (__pxxGetInterface): all should be checked for what the
caller does with -1.

The 20 pyparser.inc sites are NilPy runtime lookups (pyvar_*, pyclsattr_*,
PyNotSubscriptable, ...). pylib/pyeval are always loaded in a NilPy program,
so absence there is likely a build-configuration question, not a program-
shape one.

## What to do

For each site: write the smallest default-profile program that reaches it
without naming anything that pulls the helper's unit in, then check the output.
Where it can be reached, either pull the unit in (a pre-scan trigger) or make
it an Error naming the helper. Do not blanket-convert: `--no-default-rtl` (the
compiler's own build) and the ESP bare profile legitimately lack some helpers,
and gate quick doesn't build every profile.
