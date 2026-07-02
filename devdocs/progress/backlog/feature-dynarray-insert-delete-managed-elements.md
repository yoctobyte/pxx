# Dynarray Insert/Delete: managed elements, record/set Insert, field/element targets

- **Type:** feature (compiler intrinsic — extension) — Track A
- **Status:** backlog
- **Opened:** 2026-07-02, follow-up filed while landing
  [[feature-dynarray-insert-delete]] (v132) per its staged plan.

## Remaining scope (each a clean compile error today)

1. **Managed element types** (`array of AnsiString`, managed-field records,
   nested `array of array of T`): the fresh-temp raw byte copy shares element
   handles with the OLD buffer, and the old buffer's element-aware release
   (IR_STORE_SYM's release-old) would dangle them. Needs element retain on
   copy-in (kept elements) and element release for the deleted range —
   PXXRecordRetain / PXXDynArrayRelease-style descriptor walk over the
   affected ranges, or per-element loops in new helper variants.
   Error: `managed or nested element type not yet supported`.
2. **Record/set element Insert**: the gap store is a scalar IR_STORE_MEM;
   records/sets need an IR_COPY_REC-style memory copy from the value's
   address (value must then be an addressable lvalue, or spill the rvalue
   to a temp first). Delete already handles non-managed records fine.
3. **Non-IDENT targets** (`obj.field`, `a[i]` sub-arrays): the lowering reads
   the source symbol directly (AN_DYN_COPY has the same restriction) and the
   write-back uses the plain-symbol store path. Needs address-based source +
   IR_STORE_DYN-style write-back.
4. **FPC's array-splice form** `Insert(srcArr, arr, index)` (insert a whole
   array, not one element).
5. **riscv32 / xtensa prologue nil-init for SymIsHiddenArgTemp**: only
   x86-64/i386/arm32/aarch64 backends implement the codegen-prologue nil-init
   for lowering-time managed temps, so an in-proc dynarray
   Insert/Delete/Copy on riscv32 could release a garbage handle on first
   use. Same pre-existing envelope as array-of-const temps and materialised
   managed-string args (xtensa/ESP excludes these helpers anyway); fix is
   mirroring the 10-line prologue loop into those two backends.

## Acceptance

`Delete`/`Insert` on managed-element arrays are refcount-correct (no leak,
no double-free — extend test_dynarray_insert_delete.pas with an AnsiString
section + churn loop); record/set Insert works; self-host byte-identical.
