---
slug: feature-a-record-rtti-descriptors-for-initializearray-and-finalizearray
title: "`System.InitializeArray` / `FinalizeArray` — the RTTI-driven form of a management operator"
track: A
prio: 40
type: feature
status: working
owner: frankA
found: 2026-09-06
found-by: frankS
blocked-by: []
summary: "MEASURED 2026-09-06 at 88a0b3d93835. `InitializeArray(P, TypeInfo(TFoo), N)` and its Finalize twin do not exist -- `undefined variable (InitializeArray)`, and nothing in compiler/ or lib/rtl mentions either name. They are the RTTI-DRIVEN form of a management operator: given a raw pointer, a TypeInfo and a count, run the record's Initialize/Finalize over N elements. FPC's own RTL uses them wherever the element count is not known at compile time, which is why the SYNTACTIC form ([[feature-pascal-management-operators-nested-and-array]]) cannot subsume them -- that one desugars an lvalue it can see, this one is handed a pointer and a descriptor. THREE CORPUS ROWS ASK FOR IT, one cause: fpc testsuite tmoperator2 (line 100), tmoperator3 (line 82), tmoperator9 (line 48), all three stopping on the same undefined name. PREDICTED BY THE TICKET IT IS NOT PART OF: nested-and-array's Sketch says the dynamic-array and class-field cases are 'genuinely the RTTI shape FPC uses ... the point at which a Track A ticket for record RTTI descriptors is the right answer'. This is that ticket, filed with the demand attached rather than as a shape. TWO HALVES AND ONLY THE SECOND IS THE HARD ONE: the System helpers are a loop over a descriptor, but TypeInfo(TRec) must first CARRY the management-operator entry points for a record, which is a Track A RTTI-emission question, not a parser one. NOTHING PAST THE FAILING LINE IS VERIFIED in any of the three rows -- each stops at its first InitializeArray, so what those files assert afterwards is unmeasured and must not be quoted as passing or failing."
---

# `System.InitializeArray` / `FinalizeArray`

- **Type:** feature — Track A (RTTI emission), with a small Track P/B surface
- **Found:** 2026-09-06, walking the fpc-testsuite `tmoperator` cluster

## The shape the corpus asks for

```pascal
GetMem(PF, SizeOf(TFoo));
InitializeArray(PF, TypeInfo(TFoo), 1);   { runs TFoo.Initialize on PF^ }
...
FinalizeArray(PF, TypeInfo(TFoo), 1);     { runs TFoo.Finalize }
FreeMem(PF);
```

`tmoperator2.pp:100`, `tmoperator3.pp:82`, `tmoperator9.pp:48` — three rows,
one `undefined variable (InitializeArray)`. `grep` finds neither name anywhere
in `compiler/` or `lib/rtl`.

## Why the syntactic ticket cannot absorb this

[[feature-pascal-management-operators-nested-and-array]] generalises
`WrapManagementOpsRange` from a symbol to an **lvalue node it can see**. These
helpers are handed a **pointer and a descriptor**: the element type is a runtime
value. No amount of desugaring reaches it. That ticket's own Sketch says so and
names this one as the answer.

## The two halves, and the second is the work

1. **The helpers** — `InitializeArray(P, Info, N)` / `FinalizeArray` walking N
   elements and calling through the descriptor. A loop; small.
2. **The descriptor** — `TypeInfo(TRec)` must carry a record's management-operator
   entry points. That is RTTI emission (`rtti_emit.inc`), and it is the half
   that decides what shape 1 can even have. **Do not start with the helpers**:
   a helper written against a descriptor that does not exist yet is a guess
   about a layout somebody else will choose.

## What is NOT established

Each of the three rows stops at its FIRST `InitializeArray`. **Everything those
files assert afterwards is unverified** — a compile that stops at line 100 says
nothing about line 101. When the helpers land, re-measure all three rather than
assuming they go green; two of them also exercise `New`/`Dispose` and class
fields above the failing line, which pass today, and one exercises shapes below
it that nobody has run.

## Gate

`make compiler/pascal26` (self-host fixedpoint), the three corpus rows diffed
against fpc 3.2.2 **including exit codes** (they `Halt(n)` with distinct n per
assertion, so an exit code names the row that failed), and `tools/gate.sh quick`.

## 2026-09-07 (frankA) — a FOURTH consumer, and it is not a corpus row

`SetLength` on a dynamic array of a record declaring Initialize/Finalize needs
this descriptor, and it is the reason
[[feature-pascal-management-operators-nested-and-array]] cannot close its
dynamic arm in the parser.

Measured against fpc 3.2.2 (`var d: array of TFoo`, SetLength 3 -> 5 -> 2):
Initialize runs INSIDE `SetLength` on the elements that come into existence,
Finalize runs INSIDE `SetLength` on the elements that stop existing, and the
survivors are finalized at scope exit. A scope-entry loop over `Length(d)`
initializes zero elements and never sees one created later.

That makes the demand for this ticket broader than the three `tmoperator` rows:
**every dynamic array of a managed record in any program**, not a testsuite
shape. `SetLength` holds a pointer and an element size and nothing else, so the
grow/shrink paths are exactly the "handed a pointer and a descriptor" case the
summary above already names as unreachable by desugaring — the same argument,
arriving from a second direction.

Unchanged by this note: start with the DESCRIPTOR half. A `SetLength` hook
written against a descriptor that does not exist yet is the same guess as a
helper written against one.

## 2026-09-07 (frankA) — the descriptor half, measured before designing: most of it already exists

Claimed and read. The ticket says the descriptor is the half that decides what
shape the helpers can have, and warns against writing a helper against a layout
somebody else will choose. So: what is already chosen.

### There IS a record layout descriptor, and a runtime that walks it

`EmitLayoutRTTI` (`compiler/rtti_emit.inc`) emits one per record, `UClsRTTIOff[ci]`,
and `TypeInfo(TRec)`'s `DataPtr` already points at it (the `TYPEINFO_REQ_CAT_RECORD`
arm, `rtti_emit.inc:1305ff`). Format, read off the emitter:

```
+0   Int32   Kind = 1 (Record)
+4   Int32   Size
+8   Int32   MemberCount
+12  member[MemberCount], 16 bytes: { Offset, Kind, ArrCount, TypeRef }
     dyn[dCount],         20 bytes: { Kind=2, ElSize, Depth, BaseKind, BaseTypeRef }
```

And the runtime entry points the ticket describes as needing to be written
**already exist** in `compiler/builtin/builtinheap.pas`:

- `PXXRecordInitialize(recAddr, desc)` / `PXXRecordFinalize(recAddr, desc)` —
  and their headers say exactly why: *"a record conjured from GetMem is just
  bytes to it"*, which is this ticket's own case.
- `PXXRecordRelease` / `PXXRetain` / `PXXRecordZeroManaged` / the `...Intf` pair.

So `InitializeArray(P, TypeInfo(TFoo), N)` is close to a loop over
`PXXRecordInitialize(P + i * Size, GetTypeData(ti))`, with `Size` already in the
descriptor. **That is a smaller job than the ticket's summary implies, and it is
still not the whole job**, because of what the descriptor does NOT carry.

### What is missing, and the two constraints that shape it

**1. The management-operator entry points are not in the descriptor at all.**
`PXXRecordInitialize` zeroes managed members; it does not and cannot run a
record's `class operator Initialize`, because nothing in the blob names it. That
is the field this ticket exists to add.

**2. A record with operators but NO managed fields gets NO descriptor.** Pass 1
is guarded by `RecordHasManagedFields(ci + REC_UCLASS_BASE)`. `TFoo = record n:
Integer; class operator Initialize; end` is exactly that shape and it is the
shape every fixture in the management-operator family uses. The emission
condition has to widen, or the feature is invisible on its own test cases.

**3. The header is 12 bytes of Int32, so members start 4 mod 8.** A pointer slot
cannot go at +12 on a 64-bit target. Either the header grows to 16 (members move
to +16) or the operator pointers live at the end of the blob.

### The consumer census, because a header change moves every member walk

Enumerated rather than estimated. Emitter side, `compiler/rtti_emit.inc`: six
sites — `DataPutZeros(12 + mCount*16 + dCount*20)` ×2, `mHdr := hdr + 12 + k*16`
×2, `dynDescOff := hdr + 12 + mCount*16 + dynIdx*20` ×2. Runtime side,
`compiler/builtin/builtinheap.pas`: `memberPtr := Int64(desc) + 12` in
`PXXRecordZeroManaged`, `PXXRecordRetain`, `PXXRecordRetainIntf`,
`PXXRecordReleaseIntf`, `PXXRecordRelease` and `PXXClassFinalize`. Nowhere else
in the tree.

**THE TRAP, AND IT WOULD BE SILENT.** `Int64(desc) + 12` occurs EIGHT times in
`builtinheap.pas` and only SIX of them are this descriptor. The other two are
`baseKind := PInt32(Int64(desc) + 12)^` in `PXXDynArrayRelease` and
`PXXDynSetLen`, which walk the **dyn-array** descriptor (Kind = 2), where +8 is
`Depth` and +12 is `BaseKind`. **One literal, two blobs, one file.** A blind
`sed 's/desc) + 12/desc) + 16/'` corrupts every dynamic-array release in the RTL
and nothing about it looks wrong. The discriminator is the assignment target
(`memberPtr` vs `baseKind`), not the constant.

Also NOT to be changed: `subDesc := Pointer(memberPtr + 12 + typeRef)` inside the
member loop. That 12 is the offset of the member's own `TypeRef` slot and the
reference is **self-relative**, so a header resize does not touch it.

### The shape I propose, and the one I reject

**Propose:** grow the header to 16 — `+12 Int32 Flags` — members at +16, and put
the operator pointers at the END of the blob, 8-aligned, with a bit in `Flags`
saying they are there. Twelve sites change by one constant each, the 16-byte
member stride and the self-relative subDesc are untouched, and an old consumer
reading `Flags` as zero behaves exactly as today.

**Reject:** a new `Kind = 3` for "record with operators". It doubles the
dispatch in precisely the six routines that must never get a record's kind
wrong, to save a header word.

### Not yet measured, and it gates the first line of code

Whether `DataPutZeros`/`PatchDataI32` and the fixup pass can place an 8-aligned
pointer at a computed tail offset, and what `AddDataPtrFix` needs to relocate a
PROCEDURE address rather than a data address — every existing `AddDataPtrFix`
call in this emitter points at `Data[]` or a string, not at code. That is the
next reading, and until it is taken, the layout above is a proposal and not a
decision.
