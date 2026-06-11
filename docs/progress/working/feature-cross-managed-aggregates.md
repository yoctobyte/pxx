# Cross-target managed aggregates (records + dynamic arrays)

- **Type:** feature
- **Status:** working
- **Owner:** claude
- **Blocked-by:** feature-rtti-layout-table
- **Opened:** 2026-06-11

## Goal
Make managed records and dynamic arrays work on the 32-bit cross targets
(i386, ARM32) and bring AArch64 up to heap/string/record parity, all riding on
the Tier B target-independent layout-RTTI helpers in `builtinheap.pas`.

## Done (2026-06-11)
- **i386 + ARM32: full managed aggregates.** Records (`IR_COPY_REC` /
  `IR_COPY_REC_MANAGED` / `IR_DEFAULT_MEM`) and dynamic arrays (`SetLength` via
  the new portable `PXXDynSetLen` helper, `Length`, `IR_LEA` dyn-array
  auto-load, indexing). `IR_LOAD_MEM` accepts pointer-sized handles. Covers
  scalar + AnsiString/managed-record element arrays, grow/shrink with prefix
  preservation. v1: no copy-on-write on dyn-array writes (single-owner).
- **`PXXDynSetLen(slotAddr, newLen, desc)`** in builtinheap replaces the
  ~250-line inline x86-64 SetLength — one target-independent helper reading
  elSize/depth/baseKind from the layout descriptor. Plus portable `PXXMemMove` /
  `PXXMemZero`.
- `writeELF32` applies `DataPtrFix` (32-bit value fits low dword of the 8-byte
  slot). Method/ProcAddr fixups still blocked on i386/arm32.
- **AArch64: heap + records-infrastructure level.** `EmitHeapAllocLockedA64` /
  `FreeLockedA64`, GetMem/FreeMem, `IR_FIELD`, `IR_INDEX`, `IR_CONST_STR`,
  `EmitLoadDataRefA64`; guard relaxed (heap allowed, string/exception blocked).
  aarch64 ELF writer (shared `writeELF64`) already applies DataPtrFix.
- Tests `test_cross_record.pas` (i386+arm32), `test_cross_dynarray.pas`
  (i386+arm32), `test_cross_heap.pas` (now aarch64 too) — all oracle vs x86-64.

## Remaining
1. **AArch64 managed strings + records + dynarrays.** aarch64 has heap + FIELD +
   INDEX + CONST_STR. What's left is purely **mirroring the ARM32 string/record/
   dynarray IR ops in A64 encodings** (no new design — helpers all portable):
   - String helpers `EmitStrIncRefA64` / `EmitStrDecRefA64` / `EmitAnsiStringFromNodeA64`.
   - `IR_STORE_SYM` / `IR_STORE_MEM` tyAnsiString publish, `IR_BINOP` concat
     (`PXXStrConcat`) + eq/neq (`PXXStrEq`), `IR_WRITE` tyAnsiString.
   - Records: `IR_COPY_REC` / `IR_COPY_REC_MANAGED` / `IR_DEFAULT_MEM` (8-byte
     handles — call `PXXRecordRetain`/`Release` + `PXXMemMove`).
   - Dynarrays: `SetLength`(-102)→`PXXDynSetLen`, `Length`(-44), `IR_LEA`
     dyn-array auto-load.
   - CheckScalarSym / param-copy / epilogue / managed-local zero-init pointer-
     sized allowances; drop the aarch64 string guard; skip `EmitAnsiStringRuntime`.
   Reference: the ARM32 implementations in `ir_codegen_arm32.inc` (lines ~165-292
   for helpers, the tyAnsiString branches in STORE_SYM/STORE_MEM/BINOP/WRITE, and
   the dyn-array/record cases) — aarch64 is 64-bit so widths are 8 bytes (closer
   to x86-64) but instruction style is ARM-like.
2. **i386/arm32 string gaps** (deferred): managed-local release at scope exit
   (v1 leaks), class instantiation, exceptions.

## Test plan
Per target: `make test-i386 / test-arm32 / test-aarch64` stay oracle-matched to
x86-64; `make test` + threadsafe self-compile unbroken; self-host fixedpoint.
