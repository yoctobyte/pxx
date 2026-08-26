---
track: A
prio: 40
type: bug
blocked-by: [decide-rtti-kind-numbering]
summary: "typinfo.pas documents RetKind / TypeKind / ParamKinds as Ord(TTypeKind) and declares TTypeKind as FPC's enum (Int64 = 19), but the compiler fills those fields with its OWN internal TTypeKind (Int64 = 13). A user comparing a reported kind against the enum in the same unit gets a silently wrong answer; the unit's own TypeKindSize/TypeKindSigned already decode the compiler numbering, so the two halves of one file disagree."
owner: opus5-frank1
---

# RTTI kind numbers are the COMPILER's enum, while the unit documents FPC's

- **Type:** bug (silent wrong answer, no crash) — Track A (`rtti_emit.inc` fills
  it, `lib/rtl/typinfo.pas` declares and documents it)
- **Status:** done
- **Opened:** 2026-08-21, found while wiring the RTTI tests in
  [[chore-a-sweep-the-unwired-tests-into-the-suite]] — the tests print
  `retKind=13` for an `Int64` result, which sent me to check what 13 means.

## Measured

```pascal
uses typinfo;
...
mi := GetMethInfoByName(cls, 'F');       { function F(x: Int64): Int64 }
WriteLn(mi^.RetKind);                    { 13 }
WriteLn(Ord(tkInt64));                   { 19 }
if mi^.RetKind = Ord(tkInt64) ...        { DISAGREE }
```

## Why the two numbers exist

- `lib/rtl/typinfo.pas:120` declares `TTypeKind` deliberately in **FPC's** order
  (`tkUnknown, tkInteger, tkChar, tkEnumeration, tkFloat, tkSet, tkMethod, ...`),
  with a comment explaining that this is so FPC-written code just works. There
  `tkInt64` = 19, `tkRecord` = 13.
- `compiler/defs.inc:1416` has the compiler's own `TTypeKind`
  (`tyUnknown, tyInteger, tyBoolean, tyChar, tyString, tyRecord, tyClass, ...`),
  where 13 = `tyInt64`, 6 = `tyClass`, 5 = `tyRecord`.
- `rtti_emit.inc` writes the **compiler's** ordinals into `PMethInfo.RetKind`,
  `PMethInfo.ParamKinds` and `PFieldInfo.TypeKind`.
- But those fields are documented, in the same file that declares the other
  enum, as *"Ord(TTypeKind) of the return type"* (`typinfo.pas:45`, `:46`, `:60`).

The file already contradicts itself in code, not just in prose:
`TypeKindSize` / `TypeKindSigned` (`typinfo.pas:254`, `:262`) decode
`tk = 1, 11, 12` as 4-byte integers — correct for the COMPILER's numbering
(`tyInteger`, `tyInt32`, `tyUInt32`) and nonsense for the declared one
(`tkInteger`, `tkVariant`, `tkArray`).

## Why it matters

It is the failure mode this repo pays most for: no crash, no diagnostic, a
plausible wrong value. `if mi^.RetKind = Ord(tkInt64)` reads as obviously
correct, and is obviously wrong, and the compiler and the RTL will both keep
insisting they are right.

## The fork (state it, do not guess) — ESCALATED to [[decide-rtti-kind-numbering]] on 2026-08-22

1. **Make the RTTI fields carry FPC's numbering** — map at emit time in
   `rtti_emit.inc`. Best for FPC-source compatibility, which is the stated
   reason the FPC-ordered enum exists at all. Costs a mapping table and a
   sweep of every current reader (`TypeKindSize`, `TypeKindSigned`, the
   pyexec bridge, both RTTI tests).
2. **Keep the compiler's numbering and stop calling it `TTypeKind`** — declare a
   separate `TPxxTypeKind` in typinfo with the compiler's order, retype the RTTI
   fields to it, and fix the three doc comments. Cheapest, honest, and leaves
   FPC-source `array[TTypeKind]` code working — but the two enums stay adjacent
   in one unit, which is how this happened.
3. Expose a converter both ways and document which is which. Most code, least
   deletion of cases.

**Recommendation: (2), plus a named-constant block**, because the RTTI blob's
numbering is a compiler ABI — changing it (option 1) breaks any already-compiled
consumer, and the value of matching FPC here is small: nobody ports FPC code
that reads *our* method-RTTI blob, whereas plenty of code does
`array[TTypeKind] of X`, which option 2 leaves untouched.

## Gate

Track A's: `make compiler/pascal26` (byte-identical fixedpoint) +
`tools/gate.sh quick`, plus the two RTTI tests wired by the sweep, whose printed
kind numbers are the thing that changes if option 1 is taken.

## Outcome — 2026-08-26

Fixed as **option 3**, not the option 1 that `decide-rtti-kind-numbering` had
recorded on 2026-08-25. That decision has been **re-decided in place** with the
measurement that overturned it; the 2026-08-25 record is kept intact above it.

### Why option 1 was not taken

The 2026-08-25 derivation removed the ABI objection correctly (pxx is a
whole-program compiler, so no consumer can be older than its emitter) and then
priced the reader sweep as four mechanical edits. Measured, it is ~40 sites in
`pylib.pas`/`pyeval.pas`, **and they are ABI trampoline selection, not
type-identity tests** — `lib/rtl/typinfo.pas` says so itself: *"Code + Arity +
RetKind + ParamKinds, what the generic native-call trampoline needs."*

`PxxTkToFPCKind` is lossy in exactly those distinctions, because FPC keeps width
in `TOrdType` and float precision in `TFloatType` rather than in the kind word:

- `tySingle`/`tyDouble`/`tyExtended` all map to `4` (tkFloat), while
  `pyeval.pas:294`'s `TK_DOUBLE = 19` selects an **xmm-64-returning** proc
  pointer. A Single-returning host method would be read 64 bits wide. No value
  of an FPC-numbered field can separate them.
- `TypeKindSize`/`TypeKindSigned` answer a width and a sign from the kind word,
  and `SetOrdProp` picks `PUInt8^ / PUInt16^ / PInt32^ / PInt64^` **for the
  store** from that width. FPC's `tkInteger` spans 1, 2 and 4 bytes, signed and
  unsigned, so a published `Byte` property would be written 4 bytes wide —
  adjacent-field corruption, silently.
- Unmapped kinds map to `0`, and `pylib.pas:4635` reads `RetKind <> 0` as *"is a
  function"*, so an unmapped return type silently becomes a procedure.
- The two spaces **overlap with different meanings** on 1, 2, 11, 15, 18, 19
  (pxx 15 NativeInt vs FPC 15 tkClass; pxx 19 Double vs FPC 19 tkInt64), so a
  missed reader in a 40-site sweep picks a wrong ABI without a diagnostic.

Option 1 would also have needed a width/precision sub-field added to
`PMethInfo`, `PFieldInfo` **and** `PPropInfo` to be implementable at all —
*adding* a mechanism where the derivation expected to delete one.

### A fourth field neither this ticket nor the decision named

`TPropInfo.OrdType` (`typinfo.pas:234`) is a fourth kind word in the compiler's
numbering — it is what `GetOrdProp`/`SetOrdProp` feed to `TypeKindSize`. A
"route the three words through `PxxTkToFPCKind`" edit would have left it behind,
in the field that decides how many bytes a reflective store writes.

### What landed

The 2026-08-25 line is kept — *the typinfo facade speaks FPC's public
numbering; the compiler's internal tags stay ours and stay private* — with the
seam moved to where it holds: **a converter at the read boundary, not a
conversion at emit.** The facade (`TypeInfo()`'s `TTypeInfoHdr.Kind`,
`GetTypeData`) already speaks FPC numbering and is untouched; the four blob
fields are the private half and keep pxx's numbering.

- `lib/rtl/typinfo.pas` — a `pxxTk*` constant block (0..26) declaring the
  compiler's numbering as what it is, with the overlap spelled out, so the raw
  fields are *spellable* (`mi^.RetKind = pxxTkInt64`) and not only
  mis-spellable.
- `PxxKindToTypeKind()` — read-side twin of `PxxTkToFPCKind`, documented as
  many-to-one and irreversible, so `PxxKindToTypeKind(mi^.RetKind) =
  Ord(tkInt64)` is the correct FPC-shaped spelling. The duplicated table is
  deliberate and now cross-referenced from both sides (one lives in the compiler
  binary, one in every compiled program; no shared source exists).
- The six doc comments that asserted `Ord(TTypeKind)` corrected: `RetKind`,
  `ParamKinds`, `TFieldInfo.TypeKind`, `TPropInfo.OrdType`, `GetMethInfoByName`,
  `GetFieldPtr`.
- `TypeKindSize`/`TypeKindSigned` now carry a note saying decoding the
  compiler's numbering there is deliberate, why, and not to "fix" it.
- No emit-side change, so no reader sweep and no RTTI byte changes.
- `TTypeKind` keeps its name and its FPC order. No second enum was added —
  constants, so the "two adjacent enums" smell the 2026-08-25 note objected to
  does not return.

### Measured

`test/test_rtti_kind_numbering.pas` (+ `.expected`, wired into `test-core`)
pins both directions, including the ticket's own repro:

```
RetI64 = Ord(tkInt64)?      FALSE      { the trap, still false, now documented }
RetI64 = pxxTkInt64?        TRUE
RetI64 converted = tkInt64? TRUE
RetDbl  raw=19 asFPC=4                 { pxx 19 Double vs FPC 19 Int64 }
field B raw=8 asFPC=1   width=1 signed=FALSE
Single/Double both tkFloat?   TRUE     { the loss that rules option 1 out }
UInt8/Int32 both tkInteger?   TRUE
...but widths still differ:   1 vs 4
pxx 15 -> 1 (tkInteger=1), while Ord(tkClass)=15
```

The Makefile comment beside the two older RTTI rows, which predicted *"if that
ticket is taken, these two rows change with it"*, is updated: they do not.

### Gate

`make compiler/pascal26` byte-identical (78c16ae95b03) · `tools/gate.sh quick`
GREEN · pascal-conformance 346/0/170/34 · c-conformance 220/0 · fgl 7/7 · the
five existing RTTI tests byte-identical output.

## Log
- 2026-08-26 — resolved, commit 7d2c984f8.
