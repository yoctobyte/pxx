---
track: A
prio: 55
type: refactor
blocked-by: []
status: backlog
tags: [cross-target, wasm32, managed-locals, root-cause]
summary: "One concept — release a frame's managed locals at scope exit — is implemented seven times: symtab.inc EmitManagedLocalCleanup (x86-64), five hand-written arms in ir_codegen.inc (i386/arm32/aarch64/xtensa/riscv32), and WasmEmitManagedLocals in ir_codegen_wasm32.inc. Measured 2026-09-06: the five register arms are decision-for-decision identical and the wasm32 copy was missing a whole row (fixed, d58828d8c) and still consults neither skip predicate. CLAUDE.md's rule is that three mechanisms for one concept is a design flaw; this is seven, and the copy that drifts is never the one anyone measures."
---

# The scope-exit managed-local release loop has seven copies

## The census, measured not asserted

`EmitManagedLocalCleanupForTarget` (ir_codegen.inc:13943) dispatches on
`TargetArch`. Extracting each arm's decision chain and the helpers it calls:

| copy | where | lines |
| --- | --- | --- |
| x86-64 | delegates to `EmitManagedLocalCleanup`, symtab.inc:14023 | 234 |
| i386 | ir_codegen.inc arm | 195 |
| arm32 | ir_codegen.inc arm | 197 |
| aarch64 | ir_codegen.inc arm | 170 |
| xtensa | ir_codegen.inc arm | 176 |
| riscv32 | ir_codegen.inc arm | 206 |
| wasm32 | `WasmEmitManagedLocals`, ir_codegen_wasm32.inc:6737 | 196 |

The five register arms emit the same nine helpers in the same order —
`PXXIntfRelease PXXArrayReleaseImmediate PXXStrDecRef PXXVarClear PXXObjRelease
PXXPromoClear PXXRecordReleaseIntf PXXRecordRelease PXXDynArrayRelease` — and
carry the same decision chain, i386 differing only in hoisting `Kind = skLocal`
out of the loop. So today the five are IN SYNC. That is the finding, not the
absolution: they are in sync because people keep re-syncing them by hand, and
each re-sync is a chance to miss one.

## What being out of sync already cost

- **wasm32 had no `tyClass` arm at all.** Every NilPy object bound to a local
  leaked once per call, on that target only — measured `live` 1900 at N=2000
  and 7815 at N=8000 against a flat `live=1` on x86-64 for the same source.
  Fixed d58828d8c, guarded 223127f86.
- **wasm32 consults neither `SymSkipScopeExitRelease` nor
  `StacklessPersistentSlotSym`**, which the six others do. Still open —
  [[bug-a-the-wasm32-scope-exit-release-loop-consults-neither-skip-predicate]].
- The i386/arm32 static-array arm once released **element zero only** while
  riscv32 skipped the case entirely; both are recorded in the i386 arm's own
  comment. Three copies, three different behaviours, one concept.
- `SymSkipScopeExitRelease`'s own comment gives the reason it merges two
  unrelated ownership questions into one predicate: *"the emitters have six
  copies of this loop and the second copy is the one that stays broken."*
  Someone already hit this wall from the other side and worked around it.

## The shape of the fix

The per-target part of this loop is small: how to load a slot address, how to
load a slot value, how to call a helper. Everything else — walking `Syms[]` from
`Procs[CurProc].ScopeBase`, applying the skip predicates, classifying a symbol
into one of nine release kinds, choosing the helper and its argument shape — is
target-independent and is what is duplicated seven times.

So: one shared walker that yields `(symbol, helper name, argument kind)`, and a
per-target emitter with three entry points. `EmitZeroFrameSlot` and
`ManagedLocalZeroBytes` are the precedent — the zero-init half of this same pass
already asks a shared table, which is exactly why the zero half did not drift
while the release half did.

This is the case `root-cause-over-microfix.md` describes as the overhaul being
the SMALLER job: it deletes six copies of a nine-way classification.

## The trap, before anyone starts

**A green after changing this loop is not sufficient.** frankwasm applied the
correct predicate at the correct granularity, in the shape the six right arms
use, and REGRESSED two passing generator rows (recorded diff `0819a7f5f`). Two
explanations were offered for that and BOTH were refuted; neither
`f891bbe8e`'s blanket-exit precedent nor a wrong-predicate story survives
contact with the recorded diff. **The wasm32 copy differs from the other six in
a way nobody has named yet.** Name it before normalising it away, or the
refactor will encode the difference as a bug.

Positive control, verified at `cc18bc028`: a NilPy `yield 1; yield 2` prints
both on native AND wasm32. Anything landed here must keep that true.

Coverage that already exists and will move if this does:
`test/wasm/check_scopeexit.sh`, `check_intf.sh`, `check_outparam.sh`,
`check_variantptr.sh`, `check_nilpy_objlocal.sh`. Note these are not enrolled in
a tier — [[feature-t-enrol-test-wasm32-in-a-tier-so-something-samples-the-backend]]
— so they are run by hand today.
