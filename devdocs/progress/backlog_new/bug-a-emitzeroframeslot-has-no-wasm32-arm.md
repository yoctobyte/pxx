---
track: A
prio: 55
type: bug
blocked-by: []
summary: "EmitZeroFrameSlot (compiler/symtab.inc:10074) is the single owner of the zero-init contract and dispatches per target with a terminal else that calls Error. There is no wasm32 arm, so any program whose lowering mints a hidden managed temp dies with `compiler error: EmitZeroFrameSlot: unhandled target` before codegen — measured on test/test_dynarray_insert_delete.pas. It FAILS LOUD, which is the correct failure mode and the reason this is prio 55 rather than 70: unlike HeapMmap and PXXSysWrite (two chains in the same family that fail OPEN), nothing silently produces a wrong answer. Carries one open design question: the wasm32 backend now zeroes its own managed scalars in its prologue, so the arm may need to cover only the kinds that pass does not."
status: new
owner: ""
---

# `EmitZeroFrameSlot` has no wasm32 arm

- **Type:** bug (shared codegen) — **Track A** (`compiler/symtab.inc`).
- **Filed:** 2026-08-28 by the wasm32 lane (branch `wasm`), which cannot fix it
  under its own standing rule: a shared-file change is filed, not made.
- **Blocks:** any wasm32 program whose lowering mints a hidden managed temp.
  Measured: `test/test_dynarray_insert_delete.pas` dies at line 93 with
  `compiler error: EmitZeroFrameSlot: unhandled target`.

## The bug

`EmitZeroFrameSlot(frameOff, nBytes)` is described in its own header as the
ONE owner of the "a managed slot is nil before first use" guarantee. It
dispatches on `TargetArch` and ends:

```pascal
  else
    Error('compiler error: EmitZeroFrameSlot: unhandled target');
```

`TARGET_WASM32` reaches that `else`.

**This is the good failure mode and it is worth saying so.** Two sibling chains
in the same family — `HeapMmap` and `PXXSysWrite` — had no wasm32 arm and
failed OPEN, returning a plausible zero and letting a corrupt heap or a silent
program run to completion
(`bug-a-heapmmap-has-no-wasm32-arm-so-the-heap-starts-at-address-zero`,
`bug-a-pxxsyswrite-has-no-wasm32-arm`). This one has a terminal `else` that
reports, so the failure has a location and a name. That difference is exactly
why this sits at prio 55 and those sat at 70.

## The open question the arm has to answer first

As of `wasm` HEAD the wasm32 backend zeroes its OWN managed locals in its own
prologue — `WasmEmitManagedLocals` in `ir_codegen_wasm32.inc`, added with the
managed-string phase because a function's result slot is shadow-stack memory
and its first publish reads the slot to find the handle it must release. That
pass runs at codegen time over `Procs[CurProc].ScopeBase .. SymCount-1`, so it
already covers hidden temps minted during lowering, and it covers them EARLIER
(prologue) than `EmitZeroFrameSlot` does (at the current emission point).

So the two mechanisms overlap, and the arm should be written knowing which:

- **If the wasm prologue pass is the answer for scalars,** the wasm arm needs
  to handle only what that pass does not — the `> TARGET_PTR_SIZE` extents
  (records with managed fields, variants, static arrays of string), which route
  to `PXXMemZero` and are refused elsewhere on wasm32 today anyway.
- **If `EmitZeroFrameSlot` is the answer,** the wasm arm emits the store and
  `WasmEmitManagedLocals`'s zeroing half should be deleted rather than left as
  a second implementation of one guarantee — which is precisely what this
  routine's header says must not happen.

The second reading is the one that matches the file's stated design. The first
is what the wasm backend actually needs, because it has its own prologue and
never calls `EmitProcEpilog`. **This is a fork, not an oversight** — whoever
takes the ticket should decide it explicitly and record which, rather than
adding an arm beside a pass that already does the job.

## Notes

- The wasm arm itself is small: `$fp + WasmCurFrame + frameOff`, then an
  `i32.store` of zero (or a `PXXMemZero` call for a wide extent). The cost is
  entirely in the question above.
- `EmitManagedLocalCleanupForTarget` (`ir_codegen.inc:10135`) has the same
  shape and the same missing arm on the release side, and the wasm backend
  likewise does its own. Same fork, same answer; fold it in.
