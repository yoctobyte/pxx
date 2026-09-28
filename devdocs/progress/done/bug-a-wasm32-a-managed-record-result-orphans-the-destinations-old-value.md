---
track: A
prio: 70
type: bug
status: done
found: 2026-09-28
found-by: frankh-95 (cross-target leak sweep); fixed by frankD
owner:
summary: "LEAK, wasm32 only, every -O. A function returning a record with managed fields raw-copied its Result over the caller's destination without releasing the destination's old handles. `r := MkR(i)` in a loop, or a bare call whose scratch temp is reused per trip, leaked one block per call. case_arm_temp_finalize 488 -> 1925 and interface_result_temp 393 -> 1797 at 4x N; the other six targets stay flat."
---

# wasm32: a managed-record result orphans the destination's old value

frankh-95's cross-target sweep of the `assert_no_leak` rows found them growing
with N on wasm32 only. Repro:
`--target=wasm32 -dPXX_ALLOC_CENSUS test/test_case_arm_temp_finalize.pas`.

Every native epilogue (symtab's EmitProcEpilog) releases the reused
destination's managed members before copying the aggregate out. The wasm32
epilogue went straight to PXXMemMove.

## Resolution (2026-09-28)

Before the aggregate copy, the wasm32 epilogue calls PXXRecordReleaseIntf
(when the record has COM-interface members) and then PXXRecordRelease on the
destination, with the record's descriptor. Measured on wasm32:
case_arm_temp_finalize 488 -> 6, interface_result_temp 393 -> 8 (native 7 and 8).
Both rows now also run on wasm32 in the Makefile.
