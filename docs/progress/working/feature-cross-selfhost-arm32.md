# Cross self-host: ARM32 generated compiler runs under QEMU

- **Type:** feature
- **Status:** working
- **Owner:** claude
- **Blocked-by:** feature-cross-managed-string-cow
- **Unblocks:** feature-cross-bootstrap-selfhost
- **Opened:** 2026-06-13 (split from cross self-host rollup)

## Goal

Make the ARM32 compiler binary emitted by native `pascal26` work as a compiler
under QEMU. This is separate from the already-green stage-1 ARM32 emit and
target test suite.

## Current failure

Repro from repo root:

```sh
./compiler/pascal26 -dPXX_MANAGED_STRING --target=arm32 \
  compiler/compiler.pas /tmp/compiler_arm32
./compiler/pascal26 -dPXX_MANAGED_STRING --target=x86_64 \
  test/hello.pas /tmp/hello_native_to_x64
tools/run_target.sh arm32 /tmp/compiler_arm32 -dPXX_MANAGED_STRING \
  --target=x86_64 test/hello.pas /tmp/hello_arm32_to_x64
```

Observed 2026-06-13: `tools/run_target.sh arm32 /tmp/compiler_arm32 ...`
segfaults under QEMU (`rc=139`) before producing a comparable output.

## Acceptance

- The ARM32-generated compiler compiles `test/hello.pas` to x86-64 under QEMU.
- The emitted x86-64 `hello` is byte-identical to native `pascal26` output for
  the same command.
- The emitted x86-64 `hello` runs and prints `Hello, World!`.
- Then extend to `compiler/compiler.pas -> arm32` self-fixedpoint and compare
  byte-identical outputs.

## Log

- 2026-06-13 — opened with current failure (`rc=139` segfault).
- 2026-06-15 — blocker cleared: `feature-cross-managed-string-cow` is DONE
  (commit 2fbaca4), so ARM32 now has AnsiString index-write copy-on-write. This
  ticket is now Ready. Next: re-probe the `rc=139` segfault — the LowerCase/COW
  corruption that defeated the i386 self-host was a likely contributor, so
  re-run the ARM32-hosted `hello.pas -> x86_64` probe before chasing anything
  else.
- 2026-06-15 — claimed (claude). Re-probed: the `rc=139` segfault is **fixed**
  (commit 2931bf0). Root cause was *not* COW — it was a missing prologue
  nil-init of hidden owning managed-string arg temps on ARM32. The crash was in
  `PXXStrDecRef` during scope-exit cleanup: a `SymIsHiddenArgTemp` skLocal held
  a stale stack value (~a heap payload address), the `if p=nil` guard passed,
  and `PWord(p-16)^ := rc-1` wrote the refcount at `handle-16`, which underflows
  the heap mmap (header before the mapped page) → SIGSEGV. x86-64 and i386
  already nil-init these temps (`ir_codegen.inc` ~3817, `ir_codegen386.inc`
  ~2749); ARM32 lacked the pass. Added it to `IREmitMachineCodeArm32`.
  Diagnosis recipe: `qemu-arm -g 1234 /tmp/compiler_arm32` + `gdb-multiarch`,
  decode the faulting proc by structure (binary is stripped).
- 2026-06-15 — **new wall (managed-string config):** the ARM32-hosted compiler
  now starts cleanly (prints usage) but, run as
  `... -dPXX_MANAGED_STRING --target=x86_64 <src>`, fails at `pascal26:0:` with
  `Pascal define storage overflow` (lexer.inc:391). Only ~8 short built-in
  defines are registered at startup (`PasInitDefines` / `PasApplyTargetDefines`),
  so `PasDefineCharLen` can't legitimately reach `MAX_PAS_DEFINE_CHARS` (32768).
  Conclusion: `len := Length(name)` is returning a garbage (huge) value on the
  ARM32-hosted compiler for a managed-string const param, tripping the guard on
  an early define. Next: investigate ARM32 codegen of `Length()` on a
  `const s: AnsiString` parameter (and/or managed const-param passing) — the
  test suite's str-length-index test passes, so the failing pattern is likely
  Length-of-const-param specifically. NOTE: without `-dPXX_MANAGED_STRING` the
  ARM32-hosted compiler instead *hangs* on the frozen-string path — a separate
  issue, not the self-host (managed) config; ignore for this ticket.
- 2026-06-15 — sibling note: `ir_codegen_aarch64.inc` is also missing this
  hidden-arg-temp nil-init pass (only x86-64/i386/arm32 have it now). Latent on
  AArch64; flagged in `feature-cross-selfhost-aarch64`.
- 2026-06-15 — define-overflow wall **fixed** (commit 55ac9f7). It was NOT a
  const-param bug — it was `Length()` on a *var* (by-ref) managed-string param
  returning 0. A by-ref param slot holds the forwarded caller slot address
  (`&handle`), one deref short of the handle; the ARM32 `Length` builtin derefed
  only for `IR_INDEX`/`IR_FIELD` operands, not for an `IR_LEA` of a by-ref
  managed-string param. So `AppendChar`'s `len := Length(dst)` always saw 0,
  `PasOptionTail` ballooned the `-d` define name, and the guard fired. Added the
  `IR_LEA skParam IsRef tyAnsiString` clause to the ARM32 Length builtin,
  mirroring i386 (`ir_codegen386.inc` ~1708) and AArch64 (`ir_codegen_aarch64.inc`
  ~1118), which both already had it. Minimal repro: `Length(var s)` returns 0
  (const + direct return correct). Added `test/test_cross_var_string_param.pas`
  to `make test-arm32`.
- 2026-06-15 — **new wall:** the ARM32-hosted compiler now compiles past the
  define-overflow but SIGSEGVs deeper in
  `... -dPXX_MANAGED_STRING --target=x86_64 test/hello.pas` (no output file).
  Next: gdb-under-qemu the new crash PC.
