# `SetLength expects a string variable in IR codegen` on a valid array SetLength

- **Type:** bug (compiler) — **Track A**
- **Status:** backlog
- **Severity:** HIGH — rejects valid code; blocks a Track B library (vm). Loud
  (compile error), unlike the silent sibling bugs.
- **Opened:** 2026-06-22
- **Owner:** — (Track A / "sis")
- **Found by:** Track B, building the `vm` bytecode library.
- **Still open on v34** (re-verified): the name-resolution fix that landed in v34
  (0e0bbdb) does NOT resolve this — `stable_linux_amd64/default/pinned -Fulib/rtl
  examples/vm/vmdemo.pas` still fails with the same error. So this is a distinct
  bug from the paramless/name-shadowing family; `vm` heavily uses dynamic-array
  fields, so it may be in the same area Track A is working (dynarray codegen).

## Summary

A valid `SetLength` on a dynamic-array variable is rejected at IR codegen with:

```
pascal26:274: error: SetLength expects a string variable in IR codegen ()
```

The code is correct: **FPC compiles and runs it to `ALL OK`**. PXX only fails in
a sufficiently complex method — extracted into a small method the same
`SetLength` compiles fine, so this is **layout / context-sensitive**, the same
flavour as bug-impl-prescan-codegen-regression (and likely the same root in
local/temp slot allocation), but here it surfaces as a SetLength IR type-check
failure rather than silent wrong codegen.

The offending `SetLength` targets either an `array of AnsiString` field
(`FLabelName`) or `array of Integer` fields (`FOps`/`FArgs`) inside
`TMachine.Assemble` (a ~16-local method with nested loops and several other
`SetLength`s). The "expects a string variable" wording suggests the SetLength
lowering picks the wrong element-kind path for the target in this context.

## Repro (reliable, FPC-verified)

```sh
# PXX: rejected
stable_linux_amd64/default/pinned -Fulib/rtl examples/vm/vmdemo.pas /tmp/vm
#   -> pascal26:274: error: SetLength expects a string variable in IR codegen ()

# FPC: compiles + runs ALL OK (loopsum 55, factiter 120, factrec 120, subr 36/81)
cp lib/rtl/vm.pas /tmp/vm.pas; cp examples/vm/vmdemo.pas /tmp/vmdemo.pas
fpc -Mobjfpc -Fu/tmp /tmp/vmdemo.pas -o/tmp/vmf && /tmp/vmf
```

`lib/rtl/vm.pas` is the clean, Platonic repro — left in the tree exactly as
written (no workaround). The trigger is global-layout-sensitive: a hand-reduced
class method with the same field types + SetLength pattern + ~12 locals compiles
fine, so a small standalone repro is elusive; use the full unit.

## Isolated cases that DO compile (for contrast)

- SetLength on `array of Integer` and `array of AnsiString` class fields in a
  small method — OK.
- SetLength on a local `array of AnsiString` (with growth + index) — OK.
- The same `Assemble` two-pass logic inlined into a *program main body* — OK.

So neither the field type nor the SetLength pattern alone is the bug; method
complexity tips it over.

## Likely area

`SetLength` IR lowering: element-kind selection (string vs non-string managed vs
plain) reads stale/clobbered type info when the target's slot allocation is
under pressure from many locals/temps. Tie-in with
bug-impl-prescan-codegen-regression (same suspected slot/offset subsystem).

## Impact

`feature-demo-vm` is parked in `blocked/`: code complete + FPC-verified, but PXX
cannot compile it, so it is NOT wired into `make lib-test`. Unblocks when this
(and the related slot/offset bug) is fixed.

## Log
- 2026-06-22 — Filed by Track B from the vm build. FPC oracle confirms the
  source is valid; PXX rejects it only in the full-method context.
