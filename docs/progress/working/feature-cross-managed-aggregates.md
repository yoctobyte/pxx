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
- **Records, i386 + ARM32.** Wired `IR_COPY_REC` (plain rep-movsb / `PXXMemMove`),
  `IR_COPY_REC_MANAGED` (`PXXRecordRetain`/`PXXRecordRelease` + move, ARC-correct),
  and `IR_DEFAULT_MEM` (release + zero) into both backends; `IR_LOAD_MEM` now
  accepts pointer-sized handles (AnsiString/class field loads).
- `writeELF32` applies `DataPtrFix` (RTTI/layout blob data->data relocations):
  the 32-bit target fits the low dword of the 8-byte slot. Method/ProcAddr
  fixups still blocked on i386/arm32.
- Portable `PXXMemMove` / `PXXMemZero` added to `builtinheap` for backends with
  no single-instruction block move (ARM32).
- `test/test_cross_record.pas` in the i386 + arm32 suites (oracle vs x86-64).

## Remaining
1. **Dynamic arrays on i386/ARM32.** `SetLength` is currently ~250 lines of
   inline x86-64 (alloc / copy min(old,new) / zero / retain elements / publish /
   release old). Port it as a Pascal helper, e.g.
   `PXXDynSetLen(slotAddr, newLen, elemSize, desc)`, so all targets call it.
   Then wire on i386/arm32:
   - `IR_LEA` of a dyn-array sym must auto-load the data pointer (handle) in
     read mode; write mode needs `PXXDynArrayUnique` (COW) — or accept a v1
     non-COW load like the string/managed-local leak.
   - `Length(a)` = `[handle-8]`; indexing already works via `IR_INDEX`.
   - dyn-array assignment retain/release; scope-exit release (`PXXDynArrayRelease`).
   - Managed-element arrays (array of AnsiString / managed record) via the
     layout descriptor `baseKind`.
2. **AArch64 parity.** aarch64 is still gated at the runtime guard (no heap /
   string / record). Bring it up to the i386/arm32 level: heap (New/Dispose),
   managed strings, records — the helpers are already portable, so this is
   backend IR-op wiring + dropping the guard, mirroring the i386 work.
3. **i386/arm32 string gaps** (tracked, deferred): managed-local release at
   scope exit (v1 leaks), class instantiation, exceptions.

## Test plan
Per target: `make test-i386 / test-arm32 / test-aarch64` stay oracle-matched to
x86-64; `make test` + threadsafe self-compile unbroken; self-host fixedpoint.
