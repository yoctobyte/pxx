---
prio: 45  # auto
owner: agent-A
---

# Dynarray Insert/Delete: managed elements, record/set Insert, field/element targets

- **Type:** feature (compiler intrinsic — extension) — Track A
- **Status:** done
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

## Analysis note — 2026-07-03 (Track A, scoping only)

Why managed-RECORD / nested elements are the hard remainder: the retain walk
needs the record layout DESCRIPTOR's data address as a runtime value, and no
generic IR node yields one — the AnsiString slice got away with
`PXXDynArrayRetainImmediate(..., baseKind=1, desc=nil)` precisely because
strings need no descriptor. Existing desc consumers (IR_SETLEN_DYN,
IR_COPY_REC_MANAGED) carry the REC ID in a node field and each backend loads
`@data -(RECORD_RTTI_DATAREF_BASE + ci)` itself. So the clean path is either
(a) a small new IR op (e.g. IR_DYN_RETAIN_IMM: IRA=destData, IRB=len,
IRC=recId/-1, IRIVal=depth·baseKind) with per-backend desc load + helper
call — 6 backend hookups; or (b) a generic "data-ref constant" IR node
usable as a call argument, which would also unlock other descriptor-passing
helpers from IR. (b) is the better investment.

## Progress — 2026-07-03, managed-RECORD elements LANDED (+ generic IR_CONST_DATA)

The blocker fell to a small generic node: **IR_CONST_DATA(68)** — IRIVal =
Data[] offset OR a negative dataref sentinel, yields the absolute data
address in the accumulator; implemented in all 6 backends (one EmitLoadDataRef
line each) + added to every 32-bit walker's operand skip list (the 386-walker
double-execute landmine). Any IR-level call can now pass a record layout
descriptor.

- **Delete**: retain block extended — managed-field record elements call
  PXXDynArrayRetainImmediate(dest, newLen, depth=1, baseKind=3,
  IR_CONST_DATA(-(RECORD_RTTI_DATAREF_BASE+ci))) — the existing helper's
  record field-walk does the rest.
- **Insert**: kept-elements retain identically (the zeroed gap is nil-field =
  no-op for the walk); the gap store switches from raw IR_COPY_REC to
  **IR_COPY_REC_MANAGED** (retain src fields, release dest — fresh zeros, nil
  safe — then bulk copy), so the inserted value's field refs are owned by the
  new buffer.
- Parser gates relaxed (frozen-string + nested still rejected cleanly).
- Descriptor availability: every managed-field record gets a layout blob
  unconditionally (rtti_emit pass), sentinel resolves via UClsRTTIOff.

Verified: test_dynarray_insert_delete.pas grown 30 -> 35 cases (managed-record
delete/insert/self-referencing insert/delete-all/500-op churn), FPC-output
identical; standalone 100k-op churn RSS flat at 264KB; cross-checked
i386/arm32/aarch64 under qemu (identical output). riscv32: pre-existing
envelope — builtinheap defines PXX_ESP for ALL riscv32 (hosted too), so
PXXDynArrayRetainImmediate doesn't exist there and even AnsiString-element
Delete already errored identically; not a regression (candidate follow-up:
split PXX_ESP into arch vs profile in builtinheap).

**Still open**: nested `array of array of T` elements, frozen-string
elements, rvalue record/set insert values, non-IDENT targets (obj.field),
FPC array-splice Insert form. (The riscv32/xtensa SymIsHiddenArgTemp
prologue nil-init listed as item 5 landed separately in the v155-era
riscv32 bring-up — both walkers have the loop now.)

- 2026-07-19 (backlog sweep note) Items 1–2 landed and pinned (AnsiString c0105931 v141; managed-record 929f57f6/361b8685 v162). Live remainder per parser.inc:15323–15405 rejections: nested/frozen element types, non-IDENT targets (obj.field, a[i]), FPC array-splice form, riscv32/xtensa prologue nil-init.

## Progress — 2026-08-21: every remaining item closed except one, which was not this ticket's

Five landings. `test_dynarray_insert_delete.pas` grew **35 -> 71 cases**, all
diffed against FPC 3.2.2 as whole-program output (not recorded hashes), and all
re-run under qemu on **i386, aarch64, arm32 and riscv32**. Each item's churn loop
holds at **392 kB RSS** over 20000 iterations.

### The array-splice form was a BUG, not a missing feature (abc045945)

Item 4 was listed as unimplemented. It was not — it compiled, and compiled to
the wrong thing:

```
pxx: len=4 : 10 -1428160432 11 12
fpc: len=5 : 10 90 91 11 12
```

`Insert(t, s, 1)` on two `array of Integer` took the source array's HANDLE and
stored it as if it were an element. Silent wrong output with no diagnostic —
CLAUDE.md's escape rule: a compat gap that means wrong behaviour is a bug in the
owning lane, not a feature in a backlog.

The splice reuses the whole fresh-temp shape; three things differ, carried on
`AN_DYN_INSERT`'s IVal: `newLen` is `len(dest) + len(source)`;
`PXXDynInsArrFill` lays head/source/tail in so there is no gap and no gap store;
and **the retain walk that already ran over the fresh buffer covers the inserted
elements along with the kept ones** — managed elements needed no new machinery
at all. A source array whose element type does not match is now a compile error.

### Non-IDENT targets (553ac01e8), after a refactor that made them cheap (e2c4eae54)

`Delete(obj.Items, i, n)` was refused. The restriction lived in two places and
neither needed to exist once **one walker** answered the shape question:
`NodeDynDepth` / `NodeDynBaseTk` / `NodeDynBaseRec` / `NodeDynBaseSym` moved from
`ir.inc` to `ast_arena.inc`, where the parser can reach them — the parser had
grown `CopySrcDynDepth`, a hand-kept mirror its own comment admitted to, that
answered 0 for shapes the real walker knew. The mirror is deleted and its seven
call sites now call `NodeDynDepth`. Pure relocation first: the move alone
rebuilt the compiler byte-for-byte identical.

The lowering then uses AN_DYN_COPY's two arms (IR_LEA for a symbol, an ordinary
read otherwise — a read of a dyn-array lvalue IS its handle), and the write-back
is the same lvalue cloned. Which is why the target must be **re-readable**: it is
evaluated twice, so `DynTargetIsRereadable` admits name / field / dereference and
refuses anything that could carry a side effect. Indexed targets stay out —
they are safe only when the subscript is, and answering that needs a purity walk.
Covered: record field, nested record field, managed-element field, class field,
`p^.items`.

### Nested `array of array of T` — Delete (950baa9ce) then Insert (5659bc304)

AN_DYN_COPY had already worked out that three things change together, and having
one without the others is what makes this a segfault rather than a diagnostic:
stride by a POINTER (`TypeSize(tyPointer)`, not 8 — a handle is 4 bytes on the
32-bit targets), temp allocated at the SOURCE's depth so its scope-exit release
recurses, and the retain walk at that depth, where the RTL IncRefs every handle
and ignores `baseKind` — so it is passed a NEUTRAL 0/nil rather than falling into
the record arm, which would index the RTTI table with a `REC_NONE` element id.

Insert's two forms are told apart by **depth**: a source one level shallower is
an ordinary one-element insert of a sub-array; a source at the same depth is the
splice. The one-element form is the one that needed care — the buffer-wide
retain runs *before* the gap store and so sees a still-nil gap. Reordering was
the obvious move and the wrong one (the managed-string arm needs the existing
order, where the ARC store does its own retain), so the handle gets its one
reference from a separate `len=1` retain over the gap address: at depth > 1
`PXXDynArrayRetainImmediate` is a shallow IncRef per handle, so len=1 is
precisely one handle.

Ownership is pinned from both ends rather than assumed: a row REMOVED by Delete
is still readable through an earlier alias (released once, not twice); an
INSERTED row is SHARED with the variable it came from (`row[0] := 99` shows
through `m[1][0]`, FPC's semantics) and outlives the array — after
`SetLength(m, 0)` it is still readable.

### Rvalue record/set insert values (e3daa7b15)

`Insert(MakeP(8, 9), pts, 1)` was refused as "not addressable". FPC accepts it,
and so does the lowering once you notice records and sets are already
ADDRESS-valued in this IR — a record assignment builds its source operand with an
ordinary `IRLowerAST`, not an address-of. No spill temp: the callee's hidden
destination is live for exactly as long as the copy into the gap. The refusal was
a limitation of the lowering, not of the language. Managed-field record rvalues
work too, and that is the case pinned: the gap store is `IR_COPY_REC_MANAGED`,
which retains the source's fields, so the callee's temp must be released exactly
once.

One shape stays a pxx extension rather than parity: a bare `[a, b]` argument.
FPC reads it as an open-array literal and refuses the call.

### Frozen-string elements: NOT this ticket's gap — re-filed

The last open item turned out to be downstream of something bigger. In the
frozen model (`-uPXX_MANAGED_STRING`) a program cannot even
`SetLength(a, 3)` on an `array of string`:

```
pascal26:5: error: SetLength: dynamic array of record/string not yet supported
```

The element is an inline fixed-capacity buffer and no path knows its stride, so
Delete/Insert could never have been *reached* with one. Fixing it here would have
been a microfix on a symptom; it is now
[[feature-a-dynamic-array-of-frozen-strings]] (prio 30), which owns the stride
work and the removal of both exclusions.

### Also gone: item 5

The riscv32/xtensa `SymIsHiddenArgTemp` prologue nil-init landed in the v155-era
riscv32 bring-up (noted in the 2026-07-03 entry). The riscv32 run above confirms
it: 71/71 under qemu.

## Log
- 2026-08-21 — resolved, commit 34c46db12.
