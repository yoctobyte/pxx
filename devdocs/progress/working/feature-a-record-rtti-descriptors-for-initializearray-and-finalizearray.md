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

## 2026-09-07 (frankA) — the two readings taken, and the proposed layout is WITHDRAWN

Both open readings are closed. The first answers yes; the second **retires the
header-resize proposal above and replaces it**, so read the previous section as
history.

### 1. A procedure address CAN be relocated into `Data[]`, and DCE knows

Not `AddDataPtrFix` — `compiler/emit.inc:109` says in its own words that it is
*"a data->data 8-byte pointer relocation"*. The recorder that does this is
**`AddMethodFix(dataPos, procIdx)`** (`compiler/emit.inc:299`): *"Record a
code-address relocation into `Data[]`: the 8-byte slot at `dataPos` is patched
to the entry address of `Procs[procIdx]`. Every VMT slot and every RTTI method
entry goes through here. This is the ONE append point."* It resolves in
`elfwriter.inc:1802` as `addr := entry + Procs[MethodFixups[i].ProcIdx].BodyAddr`.

Two properties that matter and were checked rather than assumed:

- `dce.inc:291` marks `MethodFixups[i].ProcIdx` live, so an operator reachable
  only from a descriptor survives dead-code elimination.
- `DropBodilessMethodFixups` nils a slot whose target has no body rather than
  patching it to `.text - 1`, so a bodiless entry reads as nil and not as a
  wild address.

The kind-3 self-relative `typeRef` is anchored on `mHdr + 12` at all four sites
(1479, 1531, 1628, 1671), matching the runtime's `Pointer(memberPtr + 12 +
typeRef)`, so it is a property of the MEMBER and no header question touches it.

### 2. The header resize is unsafe, and the reason is the BOOTSTRAP

The proposal above — Flags at +12, members at +16 — would work fine if the
emitter and the runtime always shipped together. **They do not.** Every
`make compiler/pascal26` runs the OLD emitter against the NEW runtime: the seed
binary writes stage-1's `Data[]` with its own `EmitLayoutRTTI` while linking
stage-1's `builtinheap.pas` out of the working tree. No seed escapes it — the
pin included, because a seed invoked as `./compiler/pascal26` resolves `bdir` to
the live `compiler/builtin/` either way (`pasparser_proc.inc:4521`).

So stage-1 would read its own descriptors from +16 when they were written at
+12, and the skew is not benign: `memberPtr` starts at `member0 + 4`, so the
walk takes `member0.Kind` as an Offset, `member0.ArrCount` as a Kind and
`member0.TypeRef` — a self-relative delta — as the **array count**, then loops
that many times calling `PXXStrDecRef` on `recAddr + garbage`. In a compiler,
with no diagnostic.

**Measured, not reasoned** (2026-09-07, a counter behind an env gate in
`EmitLayoutRTTI`): compiling `compiler/compiler.pas` emits **19 record layout
descriptors**, 1–3 members each. Stage-1 walks them. The window is real.

### The replacement: a new MEMBER kind, not a header field

Announce the operators as a **member entry with a new `Kind` and `ArrCount` 0**,
its `TypeRef` self-relative to the operator table at the tail of the blob.

This is not the `Kind = 3` rejected above: that was the **blob's** kind at +0,
where a second value really would double the dispatch in the six walks. This is
the **member's** kind at member+4, a field that already carries seven values and
is plainly the format's extension point.

It has no bootstrap window at all. `ArrCount = 0` makes the entry inert in every
one of the six walks — each is `while j < arrayCount` around a `case kind of`
with no `else` arm, so the body never executes — which means an old runtime
walking a new blob does nothing with it and a new runtime walking an old blob
never sees one. **Both directions safe**, which is what a self-hosting build
requires and what a header field cannot give.

`PXXRecordZeroManaged` computes `subDesc := Pointer(memberPtr + 12 + typeRef)`
*before* the kind test, unconditionally — checked, and it never dereferences it
except under `kind = 3`, so a tail-pointing `TypeRef` is safe there too.

### Landed now, as the part that is verifiable on its own

`PENDING-COMMIT`:

- The descriptor format is **written down**, once, at `REC_DESC_HDR_SIZE` in
  `compiler/defs.inc`. It had no written form at all: the shape lived in twelve
  offset expressions split across the writer and the reader. The bootstrap
  finding above is recorded there as the rule for extending it.
- The six header uses in `builtinheap.pas` are now spelled `PXX_REC_DESC_HDR`,
  so they no longer share a spelling with the two dyn-array `BaseKind` reads —
  the "one literal, two blobs, one file" trap is now a difference you can see.
- A `test-core` row asserts the writer's and the reader's constants agree, with
  two presence rows in front of it, because a grep matching nothing returns the
  empty string on both sides and would "agree".
- `test/test_record_desc_subdesc_anchors.pas` covers the two **self-relative**
  anchors (a kind-3 nested record, and a kind-2 member whose baseKind is 3).
  Nothing did: the existing descriptor rows use a variant member and a promo
  member, neither of which has a sub-descriptor.

**The values are unchanged and the proof is byte-identity** —
`sha256(compiler/pascal26)` is `a359aa9be0373666` before and after all twelve
substitutions, so the spelling change provably emits the same compiler.

**The control for the new fixture**, because its printed counts cannot see the
defect it is for: with `MemberCount` emitted as zero behind an env gate, the
counts stayed byte-identical at `1000/1000` and the census went from `live=8` to
`live=9392`. The leak row is the assertion that reads the descriptor; the value
row is not.

### What is still not measured

Whether `DataPutZeros` and the tail-offset arithmetic can place an **8-aligned**
pointer table after a `dCount * 20` region — the blob is currently 4-aligned
throughout and nothing in it is a pointer today. `AddMethodFix` patches an
8-byte slot; whether it requires the slot to be aligned, or the ELF writer only
needs it in range, is the next reading and it gates the emitter change.

## 2026-09-07 (frankA) — a correction to the section above, and the release consequence

**Correction first.** The section above says *"no seed escapes it — the pin
included, because a seed invoked as `./compiler/pascal26` resolves `bdir` to the
live `compiler/builtin/` either way."* The **"either way" was not measured and is
wrong.** Run in place, `stable_linux_amd64/default/pinned --where` reports
`stable_linux_amd64/default/builtin/` — its own snapshot — which is precisely
why the `pinned builds live lib/rtl` gate row is a coherent pair.

The conclusion survives on a different fact: **seeding from the pin means
COPYING it to `compiler/pascal26`** (the recovery line in the
`$(COMPILER_STAMP)` recipe spells that out), and from there its `bdir` is the
live tree like any other seed. So the pin is no escape *because of where a seed
goes*, not because of what the pinned binary does. Landed at `30ed522b3` with
the over-broad wording; corrected here and in both copies in the tree.

### The FPC bootstrap chain does NOT hit it, and that is the release problem

`make bootstrap` is `fpc → FPC_COMPILER → BUILD_COMPILER → VERIFY_COMPILER`.
Every stage carries the **new** emitter. Every stage also links the **live**
`compiler/builtin/`: a `$(PXX_TMP)`-located binary finds no builtin dir beside
itself — `--where` prints `[MISSING]` for it — and falls through to the
CWD-relative last resort in `ParseUsesUnitBody`, with make's CWD at the repo
root. Measured with its own control: that binary compiles from the repo root and
answers `unit source not found: builtinheap` from anywhere else.

So under a header change:

| chain | emitter | runtime | coherent? | its own check |
| --- | --- | --- | --- | --- |
| `make bootstrap` (fpc-seeded) | new | new | **yes** | `cmp BUILD VERIFY` passes |
| `make compiler/pascal26` (locally seeded) | old | new | **no** | prints `converged` |

**Both pass their own checks and both binaries self-reproduce.** The single
instrument that would see the difference is the property the two chains exist to
compare — *a bootstrap from fpc 3.2.2 is byte-identical to the pin-derived
binary*. That is the release's anti-impersonation claim: a stranger who does not
trust our pin can rebuild from FPC and compare shas. A descriptor-format skew
lives exactly in the gap between the two chains, so it would arrive as a
**release-blocking sha difference with nothing else red**, produced by a
compiler that was corrupting its own memory while emitting the artefact.

This is a second, independent reason the extension must be a new member kind
rather than a header field, and it is the one that outranks the first.

## 2026-09-07 (frankA) — the alignment reading, taken; it removes the last unknown

The section above named this as gating the emitter change: whether an 8-aligned
pointer can be placed at a computed tail offset, and whether `AddMethodFix`
needs its slot aligned. Four readings, and the answer changes the shape.

**1. Emission has no alignment requirement at all.** `PatchDataU64`
(`elfwriter.inc:65`) stores byte-at-a-time into `Data[]`, so a code slot can sit
at any offset as far as the writer is concerned.

**2. A code slot in `Data[]` is 8 BYTES ON EVERY TARGET, 32-bit included.** The
i386/arm32 writer says so in its own words (`elfwriter.inc:2833`): *".rela.data:
data->data pointers and data->code method slots. **Slots are 8 bytes wide
(layout shared with 64-bit targets)**; the reloc patches the low word, the high
word stays zero."* So an operator entry is 8 bytes everywhere and the runtime
reads it as `PMachineWord(slot)^` — the full word on 64-bit, the low word on
32-bit, which is the same byte on every little-endian target we have. No
per-target width branch is needed and none should be written.

**3. The tail offset is NOT reliably 8-aligned, so the proposed shape was
wrong.** `12 + mCount*16 + dCount*20` is `(4 + 4*dCount) mod 8` — 8-aligned only
when `dCount` is odd — and the blob's own base is a bare `UClsRTTIOff[ci] :=
DataLen` with no padding, so even a corrected tail offset would not land on an
aligned absolute address.

**4. But aligning a blob is a one-liner and already the house idiom.**
`while (DataLen mod 8) <> 0 do DataPutB(0);` appears in `emit.inc` (twice),
`elfwriter.inc`, `resources_emit.inc` and `ir.inc`.

### What this changes

**Do not put the operator table at the tail of the descriptor.** Emit it as its
OWN blob, 8-aligned at its own emission point, and point the operator member's
`TypeRef` at it self-relatively — exactly the mechanism a kind-2 member already
uses for its dyn descriptor and a kind-3 member for its sub-descriptor.

That is strictly better than the tail, and not only for alignment:

- the tail arithmetic disappears, so nothing has to agree about
  `12 + m*16 + d*20` a second time;
- alignment becomes a local decision at one emission point instead of a property
  of every member and dyn count that precedes it;
- it reuses a referencing mechanism the runtime already implements and the new
  `test_record_desc_subdesc_anchors.pas` row already covers.

**Nothing is now unmeasured.** `AddMethodFix` relocates a procedure address into
`Data[]` and DCE keeps the target alive; a slot is 8 bytes on every target;
alignment is free at the emission point; and the announcement is a new member
kind, which is the only shape the bootstrap admits. The emitter change is
unblocked.
