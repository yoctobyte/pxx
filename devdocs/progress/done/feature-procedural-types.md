# Procedural types and method pointers

- **Type:** feature
- **Status:** done
- **Owner:** —
- **Opened:** 2026-06-16 (spawned from the async spawn-ABI decision)
- **Unblocks:** feature-async-coroutines

## Motivation

The async arc needed a way for a library `Spawn`/`CoStart` to call a coroutine
body `entry(arg)` — but PXX could not call a proc-typed variable with arguments
(`p(42)` was a parse error). Rather than a per-target asm entry shim, we added
**real procedural types** (standard Pascal, reusable everywhere: callbacks,
event handlers, dispatch tables) — which then made `CoStart` pure library.

## Delivered

- **Plain procedural types** (all 4 Linux targets, byte-identical): `type T =
  procedure(...)` / `function(...): R`; proc-typed var / param / global / local;
  `@Proc` and `nil` assignment; `v(args)` indirect call in statement and
  expression position; arg-count check against the signature. Side-fix: `@proc`
  (`IR_PROCADDR`) now works on i386/aarch64/arm32 (was x86-64-only).
- **Method pointers** `of object` (x86-64): a 16-byte Code/Data value;
  `m := @obj.Method` + `m(args)` injects Self. x86-64 only because **class
  instances are x86-64 only** (see feature-cross-target-feature-parity) — the
  cross codegen is in place and latent-correct for when classes land.

Mechanism: `AN_CALL_IND`/`IR_CALL_IND`; the signature is a body-less `Procs[]`
entry referenced by parallel arrays `AliasProcSig` / `SymProcSig` (per the
TSymbol-field landmine). Tests `test/test_proctype.pas` (test-core + test-i386)
and `test/test_methcall.pas` (test-core).

## Landmines (recorded)

- Type name `TProc` collides with the compiler's own internal `TProc` record
  (hard-coded in `IsRecordType`); don't name proc types after compiler-internal
  records.
- Driver loops need an explicit `IR_CALL_IND` case (emit iff statement root) or
  the i386/aarch64/arm32 `else` catch-all double-emits an expression-context
  call.

## Acceptance

`v(args)` through a proc-typed variable calls correctly (statement + expression,
all 4 targets); `@obj.Method` method pointers call with Self on x86-64; bootstrap
+ cross-bootstrap byte-identical. **Met.**

## Log
- 2026-06-16 — Phase A (plain) + Phase B (method ptrs) + `@proc` cross-port
  landed (commits 59e1f4d, 8fe957e, d84fc08). Closed.
