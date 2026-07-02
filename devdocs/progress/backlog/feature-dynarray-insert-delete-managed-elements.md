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

## Progress — 2026-07-02, item 1 (AnsiString elements) LANDED (v141)

`array of AnsiString` now works for both Delete and Insert. Shape:

- Fresh temp still raw-byte-fills from the intact old buffer, then
  `PXXDynArrayRetainImmediate(destData, newLen, depth=1, baseKind=1, nil)`
  retains every element now in the new buffer — balancing the old buffer's
  element-aware release when the assignment wrapper swaps the handle. The
  deleted range gains no ref, so the old-buffer release frees exactly those.
  (PXXDynSetLen's own copy+retain pattern, reused.)
- Insert's gap is still nil at retain time (no-op for the walk); the gap
  store is tagged tyAnsiString so IR_STORE_MEM's existing ARC path retains
  the inserted value for the array (and releases the nil gap). The value
  temp is a managed lowering-time local → SymIsHiddenArgTemp prologue
  nil-init; its own store-retain is balanced by scope-exit release.
- **Leak found & fixed in all THREE fresh-temp sites (Copy too)**: in a loop
  the temp slot still holds the previous pass's buffer, and the sizing
  `SetLength(temp, n)` copies + element-RETAINS those old elements into the
  fresh block — refs the raw fill then overwrites. 84MB RSS over a 200k-op
  churn; fixed by emitting `SetLength(temp, 0)` first (empty handle → the
  sizing call copies nothing). Churn now 3.8MB flat; non-managed churn
  still 264KB.

Gate: test_dynarray_insert_delete.pas grown to 26 cases (FPC-output
identical, incl. self-referencing insert value + 1000-op managed churn);
suite green; self-host byte-identical; pinned v141.

**Still open in this ticket**: record/set element Insert (memory store into
the gap), managed-record / nested-array elements, non-IDENT targets
(obj.field), the FPC array-splice Insert form, riscv32/xtensa
SymIsHiddenArgTemp prologue nil-init.

## Progress — 2026-07-02, item 2 (record/set element Insert) LANDED (v142)

Non-managed record and set elements now insert: the value is captured by
ADDRESS (parser requires an addressable value — var/field/element/deref;
rvalues stay a clean error) and memory-copied into the gap via IR_COPY_REC
with the element size (RecSize for records, 32 for sets). Address capture is
rebuild-safe: the old buffer stays intact until the assignment wrapper swaps
the handle, so self-referencing `Insert(r[0], r, i)` reads valid memory
(pinned in the test). The insert temp array now carries the element REC id
(descriptor/element size), mirroring Delete.

Gate: test_dynarray_insert_delete.pas at 30 cases (FPC-output identical);
suite green; self-host byte-identical; pinned v142.

**Still open**: managed-record / nested-array elements, frozen-string
elements, rvalue record/set insert values, non-IDENT targets (obj.field),
FPC array-splice Insert form, riscv32/xtensa SymIsHiddenArgTemp nil-init.
