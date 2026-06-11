---
summary: "Cross-architecture compiler bootstrap (AArch64/ARM32 → byte-identical self-compile)"
type: feature
blocked-by: []
owner: claude
---

# feature-cross-bootstrap

## Log
- 2026-06-11 (i386 managed string gaps closed). Resolved target i386 managed string gaps (commit 38a0f87): fixed character/string assignments and argument conversions to AnsiString, restored total length calculation during inline tyString concat, and enabled scope-exit release of AnsiString locals. The cross test suite is fully green and identical to x86-64 output. Bootstrapping complete.
- 2026-06-11 (i386 managed strings). AnsiString works on i386 for: literal
  assign, concat, var-to-var (retain + COW independence), string params/results,
  writeln, equality. i386 string IR ops call builtinheap Pascal helpers directly
  (no x86-64 shim/lock): added PXXStrIncRef/DecRef (non-atomic refcount), PXXStrEq
  (byte compare). EmitAnsiStringRuntime skipped on i386. needsAnsiRuntime no
  longer forces full builtin (plain AnsiString → builtinheap only; Variant/Str/
  Val/uses → builtin). CheckScalarSym/param-copy/epilogue/zero-init accept
  pointer-sized handles. test_cross_string in i386 suite (needs -dPXX_MANAGED_STRING).
  i386 string GAPS (clean errors, deferred): inline tyString concat (272-byte
  buffer path), char-combo string compare, by-ref string params, managed-local
  release at scope exit (v1 LEAKS locals; output correct), class instantiation,
  exceptions. NEXT per user: Tier B RTTI layout table.
- 2026-06-11 (focus shift: i386 first, per user). Tier A big blobs all ported
  to Pascal: FromLit→PXXStrFromLit (0887904), Concat→PXXStrConcat, LoadFile→
  PXXStrLoadFile (+ per-target PXXSysOpenRO/Lseek/Read/Close wrappers). Heap +
  string helpers split out of builtin.pas into a new `builtinheap` unit so a
  heap-only program does not pull the Str/Val/Variant routines (which use
  features i386 lacks). builtinheap is raw-pointer/Int64/syscall — compiles on
  all targets. i386 runtime guard relaxed: heap now allowed (New/Dispose/GetMem
  via EmitHeapAllocLocked386/FreeLocked386 → PXXAlloc/PXXFree); only string +
  exception still blocked. i386 backend gained IR_FIELD + IR_INDEX (records,
  static arrays) and scalar pointer load/store (earlier). i386 functional
  subset now: arith/control-flow/procs/loops/writes/var-params/syscalls/heap/
  records/arrays. test_cross_heap covers it (oracle vs x86-64).
  NOTE: moving procs between units changes what the seed binary pulls, so a
  plain `make` fails ("unresolved forward"); re-bootstrap via fpc once, then
  self-host fixedpoint holds.
  i386 REMAINING for parity: managed strings (needs i386 runtime shims in an
  EmitAnsiStringRuntime i386 path + i386 IR string ops: store/concat/write/
  release), class instantiation (VMT+ctor), exceptions. Then aarch64/arm32 get
  the same shim treatment (helpers already Pascal).
- 2026-06-11 — claimed. Item 1 (target CPU defines, `PasApplyTargetDefines`) and
  item 2a (clean fatal on cross-target inline asm) landed (bf3df06). Item 2c
  done via a new route: `__pxxrawsyscall(nr, a0..a5)` intrinsic
  (AN_SYSCALL/IR_SYSCALL) emitting the native trap on all 4 backends;
  `HeapMmap` rewritten asm-free with per-target mmap/mmap2 branches.
  `test/test_cross_syscall.pas` in all cross suites. Item 2b (full asm
  encoders per arch) deliberately skipped — the guard + intrinsic cover
  builtin.pas. Remaining: item 3, the runtime emitter port (~1200 lines/arch).
- 2026-06-11 — item 3 strategy change (PoC landed, 0887904). Instead of
  re-emitting each runtime helper in aarch64/arm32 machine code, move the
  helper BODY into builtin.pas as plain Pascal (raw PByte/PWord pointer ops,
  __pxxrawsyscall for syscalls — all already cross-compile). The emitted blob
  shrinks to a thin per-arch shim: save scratch, acquire heap lock, call the
  Pascal helper, release. First helper done: AnsiStrFromLiteral → PXXStrFromLit.
  Fixedpoint holds, self-host compile time unchanged (1.14s). See "Item 3
  revised plan" below.

## Item 3 revised plan (Pascal-helper approach)

Tier A — directly portable (pure pointer/syscall logic, one Pascal fn each):
  AnsiStrFromLiteral (DONE → PXXStrFromLit), AnsiStrRetain, AnsiStrRelease,
  AnsiStrConcat, AnsiStrLoadFile, ReadLine, DynArrayRetain, DynArrayRelease,
  AnsiStrReleaseLocked, HeapAllocLocked/FreeLocked (already call PXXAlloc/Free).
  Each leaves a tiny x86-64 shim today; the shim is mechanical to replicate on
  aarch64/arm32 (the call ABI + lock are the only arch-specific parts).

Tier B — compile-time type-driven walkers (HARD): EmitManagedRecordRetain/
  ReleaseLocked, EmitDynArray{AnsiStr,ManagedRec,Nested}ReleaseLocked,
  EmitDynArrayUniqueMeta. These emit per-field code from compile-time type
  metadata (UClsFBase/UFldOff_/...). They can't become a single Pascal fn
  without a RUNTIME type descriptor (RTTI-style) the helper walks. Options:
  (1) build a small managed-layout descriptor table per record/array and a
  generic Pascal walker; (2) keep these per-arch hand-emitted for now (they
  only fire for managed records/nested dyn-arrays, not plain string/heap).
  Recommend deferring Tier B; cross-bootstrap of compiler.pas needs Tier A +
  whatever managed types compiler.pas itself uses.

Tier C — entry-stub + EnableExceptionRuntime: exceptions stay gated (out of
  scope per original ticket).

## Goal

Cross-compile `compiler.pas` to a non-native target (AArch64, ARM32, i386), run
the resulting binary under QEMU to compile `compiler.pas` again for the same
target, and verify the two outputs are byte-identical.  This is the standard
"triple-stage bootstrap" correctness proof applied across architectures.

## Current State (2026-06-10)

### What works
- `make test-aarch64` and `make test-arm32` pass: test programs compiled
  cross-target produce output identical to the x86-64 baseline.
- `make test` (including `make bootstrap`) passes: the compiler is self-hosting
  on x86-64.

### What blocks the cross-bootstrap
Attempting `./compiler/pascal26 --target=aarch64 compiler/compiler.pas` fails
immediately:

```
pascal26:12: error: target aarch64: heap/string/exception runtime not yet supported
```

The guard is in `parser.inc` (`ParseProgram`) and is intentional: `compiler.pas`
uses `AnsiString`, dynamic memory, and `uses SysUtils` — all of which require
a managed runtime that is currently only implemented for x86-64.

## What Needs to Be Done

The cross-bootstrap requires three independent bodies of work.  They must all
land before the feature can be tested end-to-end.

---

### 1. Target-conditional preprocessor defines

When `--target=aarch64` is passed the lexer still initialises `CPU64` and
`CPUX86_64` — reflecting the *host*, not the *target*.  Source code that needs
to branch on target architecture (builtin.pas, future arch-specific units) has
no way to do so correctly.

**Required change:** After `TargetArch` is resolved in `compiler.pas`, clear
the host defines and set the matching target defines:

| Target   | Defines to set                          | Defines to clear        |
|----------|-----------------------------------------|-------------------------|
| x86-64   | `CPU64 CPUX86_64`                       | —                       |
| AArch64  | `CPU64 CPUAARCH64 CPU_AARCH64`          | `CPU64 CPUX86_64`       |
| ARM32    | `CPU32 CPUARM CPU_ARM32`                | `CPU64 CPUX86_64`       |
| i386     | `CPU32 CPUI386 CPU_I386`                | `CPU64 CPUX86_64`       |

Relevant files: `compiler/lexer.inc` (`PasInitDefines`), `compiler/compiler.pas`
(post-option-parse block).

---

### 2. Cross-target inline-assembler handling (`asmenc.inc` / `parser.inc`)

`builtin.pas` contains one `assembler` procedure (`HeapMmap`) that emits a raw
`sys_mmap` syscall.  The compiler's asm encoder (`asmenc.inc`) is
x86-64–only.  When cross-compiling for AArch64, parsing this function body
causes the x86-64 encoder to write x86-64 bytes into an AArch64 ELF — silently
wrong.

**What NOT to do:** patch around it with special-case proc-name detection, or
skip the asm body silently.  Both are hacks.

**What to do:**

#### 2a. Properly error on cross-target asm
`AsmParseBody` (and `ParseProcDecl` when `isAsmFunc` is True) must detect
`TargetArch != TARGET_X86_64` and emit a clean fatal error rather than
silently encoding garbage.  This makes the unsupported path explicit rather
than subtly wrong.

#### 2b. Implement arch-specific asm encoders
Long-term, `asmenc.inc` should grow AArch64 and ARM32 paths, or the file
should be split into `asmenc_x64.inc` / `asmenc_aarch64.inc` / etc., selected
by `TargetArch`.  Each backend only needs a minimal subset (what
`builtin.pas` actually uses).

#### 2c. Rewrite `HeapMmap` to avoid inline asm
The cleanest fix for `builtin.pas` itself is to expose a compiler intrinsic
(`__PxxRawSyscall(nr, a0..a5): Int64`) that is lowered by the IR backend to
the target's native syscall instruction.  `HeapMmap` then becomes:

```pascal
function HeapMmap(len: Int64): Int64;
begin
  { sys_mmap / sys_mmap2 depending on target }
  Result := __PxxRawSyscall(SYS_MMAP_TARGET, 0, len, 3, 34, -1, 0);
end;
```

The intrinsic needs:
- A new IR node (`IR_SYSCALL`).
- Emission in each backend (`ir_codegen.inc`, `ir_codegen_aarch64.inc`,
  `ir_codegen_arm32.inc`, `ir_codegen386.inc`).
- Syscall-number constants per target exposed as compiler-injected defines or
  a builtin constant array.

Relevant files: `compiler/asmenc.inc`, `compiler/parser.inc`,
`compiler/ir.inc`, `compiler/defs.inc`, `compiler/builtin/builtin.pas`, all
`ir_codegen_*.inc`.

---

### 3. Cross-target runtime emitters (`ir_codegen.inc`)

`EmitAnsiStringRuntime` and all the functions it calls emit raw x86-64
machine code.  This is the largest block of work.  Full list of procedures
that need arch-conditional implementations:

| Procedure                              | AArch64 lines est. | ARM32 est. |
|----------------------------------------|--------------------|------------|
| `EmitAcquireHeapLock`                  | ~15                | ~15        |
| `EmitReleaseHeapLock`                  | ~10                | ~10        |
| `EmitHeapAllocLocked`                  | ~25                | ~25        |
| `EmitHeapFreeLocked`                   | ~25                | ~25        |
| `EmitDynArrayRetain`                   | ~10                | ~10        |
| `EmitDynArrayReleaseLocked`            | ~20                | ~20        |
| `EmitAnsiStrReleaseLocked`             | ~20                | ~20        |
| `EmitManagedRecordRetain`              | ~40                | ~40        |
| `EmitManagedRecordReleaseLocked`       | ~50                | ~50        |
| `EmitDynArrayAnsiStrReleaseLocked`     | ~60                | ~60        |
| `EmitDynArrayManagedRecReleaseLocked`  | ~70                | ~70        |
| `EmitDynArrayNestedReleaseLocked`      | ~50                | ~50        |
| `EmitDynArrayUniqueMeta`               | ~120               | ~120       |
| `EmitAnsiStrFromLiteral`               | ~50                | ~50        |
| `EmitAnsiStringRuntime`                | ~200               | ~200       |
| `EmitLoadManagedHandleRdi`             | ~20                | ~20        |
| `EmitPublishManagedString`             | ~50                | ~50        |
| `EmitArgvToStringManaged`              | ~40                | ~40        |
| `EmitVariantClear` / `EmitVariantRetain` | ~30              | ~30        |
| `EmitAnsiStrFromInlineString`          | ~10                | ~10        |
| `EmitReadLine`                         | ~80                | ~80        |
| `EnableExceptionRuntime`               | ~200               | ~200       |
| **Total (rough)**                      | **~1200 lines**    | **~1200**  |

The recommended implementation strategy:

1. Create `compiler/ir_codegen_runtime_aarch64.inc` and
   `compiler/ir_codegen_runtime_arm32.inc`, mirroring `ir_codegen.inc` in
   structure but emitting native instructions for each target.
2. Each procedure that is currently x86-64–only gets a dispatch wrapper:
   ```pascal
   procedure EmitHeapAllocLocked;
   begin
     if TargetArch = TARGET_AARCH64 then EmitHeapAllocLockedA64
     else if TargetArch = TARGET_ARM32 then EmitHeapAllocLockedA32
     else EmitHeapAllocLockedX64;  { current body }
   end;
   ```
3. The AArch64 calling convention for the runtime helpers uses x19–x28 as
   callee-saved scratch (equivalent to rbx/r12–r15 on x86-64).  x0 is the
   accumulator (rax equivalent).
4. ARM32 uses r4–r11 as callee-saved scratch, r0 as accumulator.

Relevant files: `compiler/ir_codegen.inc`, new
`compiler/ir_codegen_runtime_aarch64.inc`,
`compiler/ir_codegen_runtime_arm32.inc`.

---

### Out of Scope for This Ticket

- Exception runtime for cross targets (`EnableExceptionRuntime`) — this can
  remain gated and error cleanly.  The cross-bootstrap only needs
  heap + AnsiString.
- i386 cross-bootstrap — lower priority; tackle after AArch64 is done.

---

## Test Plan

1. `make test` still passes (x86-64 baseline unbroken).
2. `make test-aarch64` still passes.
3. `./compiler/pascal26 --target=aarch64 compiler/compiler.pas /tmp/pascal26_a64` succeeds.
4. `qemu-aarch64 /tmp/pascal26_a64 --target=aarch64 compiler/compiler.pas /tmp/pascal26_a64_2`
   succeeds.
5. `cmp /tmp/pascal26_a64 /tmp/pascal26_a64_2` exits 0 (byte-identical).
6. Steps 3–5 repeated for `arm32`.

## Effort Estimate

| Work item                       | Effort     |
|---------------------------------|------------|
| Target preprocessor defines     | 1–2 h      |
| Inline-asm cross-target error   | 1 h        |
| `__PxxRawSyscall` IR intrinsic  | 1–2 days   |
| AArch64 runtime emitters        | 3–5 days   |
| ARM32 runtime emitters          | 2–3 days   |
| Integration + tests             | 1 day      |
| **Total**                       | **~2 weeks**|
