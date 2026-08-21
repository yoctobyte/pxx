---
track: A
prio: 40
type: bug
blocked-by: []
summary: "typinfo.pas documents RetKind / TypeKind / ParamKinds as Ord(TTypeKind) and declares TTypeKind as FPC's enum (Int64 = 19), but the compiler fills those fields with its OWN internal TTypeKind (Int64 = 13). A user comparing a reported kind against the enum in the same unit gets a silently wrong answer; the unit's own TypeKindSize/TypeKindSigned already decode the compiler numbering, so the two halves of one file disagree."
---

# RTTI kind numbers are the COMPILER's enum, while the unit documents FPC's

- **Type:** bug (silent wrong answer, no crash) — Track A (`rtti_emit.inc` fills
  it, `lib/rtl/typinfo.pas` declares and documents it)
- **Status:** backlog
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

## The fork (state it, do not guess)

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
