# Cross self-host: AArch64 generated compiler runs under QEMU

- **Type:** feature
- **Status:** done
- **Owner:** codex
- **Blocked-by:** feature-cross-managed-string-cow
- **Unblocks:** feature-cross-bootstrap-selfhost
- **Opened:** 2026-06-13 (split from cross self-host rollup)

## Goal

Make the AArch64 compiler binary emitted by native `pascal26` work as a compiler
under QEMU. Keep this platform-specific until the failure is understood.

## Current failure

Repro from repo root:

```sh
./compiler/pascal26 -dPXX_MANAGED_STRING --target=aarch64 \
  compiler/compiler.pas /tmp/compiler_aarch64
tools/run_target.sh aarch64 /tmp/compiler_aarch64 -dPXX_MANAGED_STRING \
  --target=x86_64 test/hello.pas /tmp/hello_aarch64_to_x64
```

Observed 2026-06-14: the native-built AArch64 compiler is produced, and the
AArch64-hosted self compile no longer segfaults in `FindProcOverload`. It now
fails deterministically while compiling the built-in heap unit:

```text
ok: /tmp/ca64  [code=2542476B  data=43368B  bss=133171336B  procs=801]
pascal26:82: error: invalid IR node reference in arg value ()
```

The previous crash was PC `0x48bda8`, fault address `0x48`, instruction
`ldrb w0, [x0]`, mapped to `FindProcOverload`. That was caused by AArch64
`IR_LEA` loading a non-byref open-array/fixed-string/set parameter slot with
the element width (`array of Boolean` loaded one byte, yielding pointer
`0x48`). The current wall is past that crash and is an IR validation failure
from an `IR_ARG` with an empty value while compiling `compiler/builtin/
builtinheap.pas` around the `HeapMmap` raw-syscall block.

## Acceptance

- The AArch64-generated compiler compiles `test/hello.pas` to x86-64 under
  QEMU.
- The emitted x86-64 `hello` is byte-identical to native `pascal26` output for
  the same command.
- The emitted x86-64 `hello` runs and prints `Hello, World!`.
- Then extend to `compiler/compiler.pas -> aarch64` self-fixedpoint and compare
  byte-identical outputs.

## Log

- 2026-06-13 — opened with current failure (`Pascal define storage overflow`).
- 2026-06-13 — diagnosis (no code change): the LowerCase crash is NOT the COW
  gap. AArch64 `IR_LEA` (`ir_codegen_aarch64.inc` ~799) only loads the heap
  handle for dyn arrays (`IsArray and ArrLen=-1`); for a scalar AnsiString it
  returns the slot ADDRESS, so `Length(s)`=0 and `s[i]` indexes the slot →
  garbage, and LowerCase's `res[i]:=...` writes to a bad address → segfault.
  This is exactly the already-fixed i386 bug #1 (IR_LEA scalar-AnsiString
  handle load). Fix first by mirroring the i386 IR_LEA change (load the handle
  for scalar AnsiString; add skParam IsArray/tyString/tySet content-load and
  by-ref-AnsiString deref-in-Length/index), THEN tackle COW
  (feature-cross-managed-string-cow). Repro: `var s:ansistring; s:='Hello';
  writeln(Length(s))` prints 0 on aarch64, 5 on x86-64. AArch64 is behind
  i386/ARM32 here — string indexing/Length isn't in its target suite yet.
- 2026-06-13 — Codex fixed the AArch64 scalar-AnsiString `IR_LEA` gap and added
  the existing `test_cross_str_length_index` oracle to `make test-aarch64`.
  `make test-aarch64` is green. The generated AArch64 compiler now gets past the
  original `Length(s)=0` class of bug, but the self-host repro still segfaults:
  GDB maps the fault to `PXXStrDecRef`, called from `ParseProgram`, with
  `p = -9`. The caller is releasing a stale local managed-string slot from
  `dummyNames: array[0..7] of AnsiString`; this is the remaining managed
  aggregate/static-array local initialization/release wall, not the old `IR_LEA`
  scalar-string wall.
- 2026-06-14 — advanced the wall. Implemented AArch64 string index-write COW
  (`PXXStrUnique` from write-mode `IR_INDEX`), explicit zeroing for hidden
  managed argument-temp locals allocated during IR lowering, AArch64 `IR_LEA`
  param-pointer loading for open-array/fixed-string/set params, and signed
  32-bit `EmitLoadVarA64` loads (`ldrsw`). `make test-aarch64` and `make test`
  pass. The full repro:
  `./compiler/pascal26 -dPXX_MANAGED_STRING --target=aarch64 compiler/compiler.pas /tmp/ca64`
  succeeds, but running `/tmp/ca64` under QEMU to produce `/tmp/ca64_self` still
  segfaults after reading `compiler/builtin/builtinheap.pas`. Latest GDB
  snapshot: PC `0x48bda8`, fault address `0x48`, instruction `ldrb w0, [x0]`;
  surrounding code forms a character access from a nil/wrong base plus a signed
  local offset. Next slice: map that proc and inspect the string/index base
  feeding the byte load.
- 2026-06-14 — fixed the `FindProcOverload` crash. AArch64 `IR_LEA` for
  non-byref parameter pointer slots (`array of T`, fixed string, set) now loads
  the full pointer-sized caller slot instead of delegating to `EmitLoadVarA64`,
  whose width follows the element type. Added
  `test/test_cross_open_array_params.pas` to lock the `array of Boolean`
  trigger used by `FindProcOverload(ptypes, parr, pbyref)`. `make test-aarch64`
  passes. Clean self-host probe now advances to:
  `pascal26:82: error: invalid IR node reference in arg value ()` while the
  AArch64-hosted compiler is compiling `builtinheap.pas` (`HeapMmap` /
  `__pxxrawsyscall`). A quick reduced probe showed any program still reaches
  this via built-in heap compilation; temporary syscall-specific parser/IR
  diagnostics did not prove a fix and were backed out. Next slice: identify the
  general call/argument lowering node that produces `IR_ARG(IRA=-1)` under the
  AArch64-hosted compiler.
- 2026-06-15 — blocker `feature-cross-managed-string-cow` is DONE (commit
  2fbaca4); AArch64 string COW was already in place, so the remaining wall here
  is independent of COW: the `IR_ARG(IRA=-1)` / `invalid IR node reference in arg
  value` crash while the AArch64-hosted compiler compiles `builtinheap.pas`.
  This ticket is now Ready.
- 2026-06-15 — latent-bug note from the ARM32 self-host work (commit 2931bf0):
  `ir_codegen_aarch64.inc` is **missing** the prologue nil-init of hidden owning
  managed-string arg temps (`SymIsHiddenArgTemp` skLocal) that x86-64, i386, and
  now ARM32 all have (`ir_codegen.inc` ~3817). On ARM32 the absence caused a
  startup `PXXStrDecRef`-on-garbage SIGSEGV. AArch64 may have masked it so far
  (its temps may land in already-zeroed BSS, or the crash here precedes that
  cleanup), but add the same pass to `IREmitMachineCodeAArch64` when chasing the
  `IR_ARG(IRA=-1)` wall — it is a likely co-factor.
- 2026-06-15 — **two walls cleared, hello byte-identical; one wall left.**
  1. **Frame size > 4 KB corrupted the stack** (commit a6750e9). `PatchProcPrologue`
     encoded `sub sp,sp,#imm` as `$D10003FF or (aligned shl 10)`, but the AArch64
     immediate is only 12 bits (bits 21:10) with an optional LSL #12. Any frame
     > 4095 overflowed the field, sp was decremented too little, calls/arg-pushes
     overlapped the locals, and the saved x29/x30 were clobbered → epilog `ret`ed
     to 0. The `IR_ARG(IRA=-1)` failure was actually this: IRVerify has a 131 KB
     local (`seenLabel: array[0..MAX_IR-1]`), so the self-hosted compiler corrupted
     its own frame and read garbage IR-node indices. Fix: frames > 4095 round up to
     a 4096 multiple and use the LSL #12 form; the epilog restores via `mov sp,x29`
     so the slack is harmless. Test `test/test_cross_huge_frame.pas`.
  2. **nil-init hidden managed-arg temps** (commit afe94f2) — the ticket's flagged
     missing pass; added to `IREmitMachineCodeAarch64`.
  After (1), the AArch64-generated compiler compiles `hello.pas` → x86-64
  **byte-identical** and runs. make test + test-aarch64 green.
  **Remaining wall — `array of const` VType corruption when targeting aarch64.**
  The AArch64-hosted compiler crashes compiling builtinheap.pas (`PXXAlloc`, the
  branch emission) with `EmitAsmA64: missing integer hole value`. Root: the
  `['b %', offset]` array-of-const that EmitAsmA64 builds has a corrupt 2nd
  element — `items[0].VType=11` (the 'b %' string) is correct, but `items[1].VType`
  reads 24 instead of vtInteger(0). NOTE: only the codegen *targeting aarch64*
  exercises EmitAsmA64; hello→x86-64 doesn't, which is why hello is byte-identical
  yet self-fixedpoint fails. Investigated and RULED OUT: (a) not a TVarRec
  stride/size mismatch — forcing `FixupTVarRecLayout` to run before builtinheap
  codegen (so RecSize(TVarRec)=16 not 24) did NOT change the 24; (b) the dyn-array
  length is correct (n=2, element 0 reads fine, so the handle is valid); (c) the
  nil-init temp pass didn't change it. So element 1's VType is genuine garbage,
  not an offset/stride artefact. Crucially the SAME `['b %', x]` construct compiled
  by the NATIVE compiler for an aarch64 *target* program runs correctly — so the
  bug only manifests in the aarch64-HOSTED compiler's runtime state (suspect a heap
  / dyn-array-of-record fill bug specific to that path). Next: add diagnostics in
  the AArch64 dyn-array-of-record element FILL (ir.inc AN_VARREC_ARRAY → the
  per-element IR_STORE_MEM) vs the READ to see where element 1's VType store lands
  vs where the read looks, on the aarch64-hosted compiler.
- 2026-06-15 — **DONE. AArch64 self-fixedpoint byte-identical.** Root cause of the
  `array of const` corruption was a target-independent dyn-array element-size bug,
  not an AArch64 codegen bug. `GetOrAllocSymRTTI` (`ir_codegen.inc` ~209) computed
  the per-element stride for the SetLength runtime descriptor as
  `TypeSize(Syms[..].ElemType)`; for an **unmanaged record** element (`tyRecord`
  with no managed fields, exactly TVarRec) `TypeSize(tyRecord)` returns the
  pointer-width placeholder **8**, not `RecSize(TVarRec)`=16. So `PXXDynSetLen`
  allocated `n*8`: a 2-element `array of const` got 16 bytes, and element 1
  (offset 16) overran into adjacent free heap. It survived only when read
  immediately; `EmitAsmA64(['b %', offset])` does string work (heap allocs)
  between constructing the array and reading the integer hole, so the overrun
  region was clobbered → `items[1].VType` read stale garbage (24 = ord(tyAuto),
  a red herring) → `EmitAsmA64: missing integer hole value`. (Only the managed
  baseKind=3 record branch right-sized via `UClsSize_`; the unmanaged baseKind=0
  branch fell through to `TypeSize`.) Diagnosis path: writer-side `DbgVarRec`
  built element 1 correctly (`0,-220`) while the very next `EmitAsmA64`-fed build
  read stale (`24,1`); raw-heap dump showed element 1's bytes were never near the
  block → under-allocation. Fix: in `GetOrAllocSymRTTI` baseKind=0, use
  `RecSize(ElemRecName)` when `ElemType=tyRecord`. Regression test
  `test/test_varrec_alloc_after.pas` (forces allocations between construction and
  the element reads; wired into `make test` and `make test-aarch64`). Acceptance
  met: `compiler_aarch64` compiles `hello`→x86-64 byte-identical and it runs; the
  AArch64-hosted compiler compiles `compiler.pas`→aarch64 **byte-identical** to
  the native-emitted aarch64 compiler (self-fixedpoint, 871 procs), and that
  self-emitted compiler compiles `hello` byte-identical. `make test` + all four
  cross suites (i386/arm32/aarch64) green; x86-64 self-host fixedpoint reconverged.
