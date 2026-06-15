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
  gdb-under-qemu: crash PC `0x0837cc90` on `stmfd sp!, {r0}` (a stack push),
  r0=0, lr=`0x083b1744`. A faulting *push* points at stack exhaustion (deep
  recursive-descent parse/codegen recursion) or sp corruption rather than a bad
  data pointer. Next: confirm by watching sp vs the mapped stack bound under
  qemu (and/or check for an ARM32 frame-size / sp-adjust bug in a hot recursive
  proc); map `0x0837cc90`/`0x083b1744` to procs by structure.
- 2026-06-15 — **HELLO MILESTONE ACHIEVED (byte-identical).** Chased the
  deeper SIGSEGV; it was three distinct ARM32 codegen bugs, each surfaced and
  fixed in turn:
  1. **Frame size > 255 bytes corrupted sp** (commit e9290e1). The faulting
     `stmfd sp!,{r0}` was an expression-eval push; sp was garbage because
     `PatchProcPrologue` ORed the raw frame byte count into ARM's *rotated*
     imm8 field. A 1376-byte (0x560) frame encoded as `0x60 ror 10 =
     0x18000000` (384 MB). Fixed by loading the frame size from a literal pool
     into r9 and `sub sp,sp,r9` (any 32-bit frame).
  2. **Open-array / string / set param base address** (commit a3b1f70).
     `EmitLoadVarAddrArm32` loaded the slot (caller pointer) only for `IsRef`
     params; an open-array `const x: array of AnsiString` also passes a pointer
     but ARM32 took the slot *address*. Indexing read the stack frame → empty
     elements + a scope-exit DecRef of garbage. Extended the branch to
     `IsRef or IsArray or tyString or tySet` (mirrors i386). Surfaced in
     RegisterProc (`const pnames: array of AnsiString`). Test
     `test/test_cross_openarray_string.pas`.
  3. **Stack-passed args (5th+ parameter) corrupted** (commit 861e4c7). The
     caller did `add sp,sp,#16` before the call to "leave stack args at [sp]",
     but stack args sit at the *low* end, so a register arg was left at [sp]
     and the callee read the wrong slot. With a stack-passed open array its
     pointer came back as a scalar (1) → segfault. Fixed both sides: caller
     keeps all args pushed for nArgs>4 (argN at [sp]) and drops nArgs*4 after
     the call; callee reads stack arg i at `[fp+8+(nparams-1-i)*4]`. Verified
     1/2/3 stack args. Test `test/test_cross_stack_params.pas`.
  After all three: `tools/run_target.sh arm32 /tmp/compiler_arm32
  -dPXX_MANAGED_STRING --target=x86_64 test/hello.pas /tmp/out` runs the ARM32
  compiler under QEMU, emits x86-64 **byte-identical** to native pascal26, and
  the result prints `Hello, World!`. First three acceptance bullets DONE.
- 2026-06-15 — **self-fixedpoint wall = ARM32 has no Int64 codegen.** The
  ARM32-hosted compiler compiles `compiler.pas -> arm32` to completion
  (rc=0, full 3.6 MB binary, 862 procs) but the output diverges from the
  native-emitted arm32 compiler by ~7424 code bytes. First diff (byte 51471) is
  a double-literal constant: native emits `1e15`, the arm32-hosted compiler
  emits `0.0`. Isolated: the arm32-hosted compiler parses **every** float
  literal to 0.0 (even `1234.5`). Root cause is the lexer's manual float-bits
  routine (`lexer.inc` ~240-332), which needs real 64-bit integer arithmetic —
  and **ARM32 integer codegen is 32-bit-only**:
  - `IR_CONST_INT` (`ir_codegen_arm32.inc` ~484) loads only the low 32 bits via
    `EmitLoadImmArm32` (Int32 param), so `$8000000000000` (2^51) → 0.
  - `IR_BINOP` (~832-851) is all single-register r0/r1: `mul r0,r1,r0` is 32-bit,
    `lsl r0,r0,r1` is a 32-bit shift (shift ≥32 → 0, so `x shl 52` → 0).
  Minimal repro: `a:=1033; b:=$10000000000000; writeln(a*b)` → arm32 prints 0
  (x86-64: 4652218415073722368); `12345*5` is correct (fits 32-bit). Next arc:
  implement ARM32 Int64 as an r0:r1 (lo:hi) register pair — 64-bit const load,
  load/store, add/sub/mul/shl/shr/div/mod/compare — mirroring the i386 edx:eax
  model. That unblocks the float-literal parser and the byte-identical
  self-fixedpoint.
- 2026-06-15 — **ARM32 Int64 codegen implemented** (commit 53456f3): r0:r1
  register-pair model — const/load/store/add/sub/mul/shl/shr/div/mod/compare,
  Int64 args+returns (word-based calling convention), writeln, Trunc/Round->Int64.
  Verified vs the x86-64 oracle (test/test_cross_int64.pas + edge-case compare and
  param/return stress tests, wired into make test-arm32). make test + test-arm32 +
  test-i386 all green.
  **This regressed the hello self-host milestone.** Enabling true 64-bit *compares*
  makes the arm32-emitted compiler fail to load builtinheap.pas
  (`pascal26:1: error: unexpected character ()`); the source reads fine (22 bytes)
  but the unit search's LoadFile then issues a corrupted `read(-2,buf,-9)`.
  Bisection: routing Int64 compares back to a 32-bit low-word comparison makes the
  self-host work again — but then the float-literal parser reparses everything to
  0.0 (it needs real 64-bit compares). So the self-host needs *correct* 64-bit
  compares yet can't survive them.
  Diagnosis: the compare LOGIC is correct (matches the oracle on all signed/unsigned
  edge cases) and i386 uses the identical scheme and self-hosts, so the cause is a
  wrong/uninitialised Int64 **high word** produced by some compiler-internal path,
  only observed once compares read the full 64 bits (a 32-bit low-word compare
  ignores it). NOT a register clobber (r2..r12 preservation around EmitBinop64
  tested, no effect). NOT the boolean result high word (clearing r1 after compares,
  no effect). Every isolated Int64 pattern tested (mem compares with bit31-set/
  negative values, returns-in-compares, params) matches the oracle — the breaking
  pattern is compiler-specific and not yet reproduced small.
  Next: gdb the arm32-hosted compiler to find the first Int64 compare whose operand
  high word differs from x86-64 (suspect an uninitialised Int64 local/slot, or an
  Int64 produced by a 32-bit path without widening); fix that, then re-check hello
  byte-identical and float-literal -> self-fixedpoint.
- 2026-06-15 — **"64-bit compare issue" ROOT-CAUSED + FIXED** (commit afc7ca0). It
  was *not* the compare codegen — it was `IR_SYSCALL` not sign-extending its
  result. `__pxxrawsyscall` is typed Int64, but the ARM32 emitter left the kernel's
  32-bit r0 result with a garbage high word. Once Int64 became a true 64-bit type,
  a negative syscall return (-errno) read as a large *positive* Int64, so
  `if fd < 0 then Exit` in PXXStrLoadFile/PXXSysOpenRO never fired: a failed open
  (-2) gave `0x00000000FFFFFFFE > 0`, and the helper ran lseek/read/close on a dead
  fd, corrupting state during every failed unit-path probe → couldn't find
  builtinheap.pas → "unexpected character". Fix: `mov r1, r0, asr #31` after `svc`.
  Diagnosis method that cracked it: `qemu-arm -strace` of the broken vs the
  compares-routed-to-32bit build, diffed at the first divergent syscall — broken did
  lseek/read on fd=-2 where working skipped them (guard failed). Result: hello
  self-host **byte-identical** again AND float literals now parse correctly on the
  arm32-hosted compiler (1e15 / 1234.5 / 3.14159265, not 0.0). make test +
  test-arm32 + test-i386 green. (Lesson: every signed value that arrives in a single
  register but is typed Int64 — syscall returns especially — must be sign-extended
  into the high word; the compares were a red herring, they just *read* the bad
  high word.)
- 2026-06-15 — **new wall: full self-fixedpoint SIGSEGV (deep).** With the syscall
  fix, the arm32-hosted compiler now reads compiler.pas + all its `.inc`s and
  compiles deep, then SIGSEGVs at `ldr r0,[r0,#-8]` (managed-string Length) with the
  handle = `0xFFFFFFFF` (-1) — the nil guard only checks `=0`, so a -1 handle slips
  through and derefs `[-9]`. fp-chain: fault proc `0x8190c2c` (its 1st param, a
  managed string, is -1) <- `0x819d43c` <- `0x819e0d4` <- `0x82e4098` <- `0x82fa6e8`.
  Single 256 MB heap mmap (no alloc failure). So a managed-string ARG of -1 is built
  several call levels up. This is an Int64-introduced regression (before the Int64
  arc the full self-compile *completed*, rc=0, only diverging on the 0.0 floats).
  Next: walk the caller chain (the -1 string is the caller's local `[fp-32]`) to the
  origin — suspect a function that returns a managed string but yields -1 on an
  error/sentinel path, or an Int64/pointer value of -1 stored into a string slot;
  fix the origin, then re-attempt compiler.pas -> arm32 byte-identical fixedpoint.
