---
slug: bug-p-a-specialization-minted-in-a-units-implementation-is-seen-by-the-importers-duplicate-test
track: P
prio: 60
type: bug
status: done
blocked-by: []
created: 2026-09-04
found-by: frankB
commit: cd44193c6
summary: "FIXED same day. A program specializing the SAME template a used unit already specialized in its IMPLEMENTATION section answered `unknown type: TBox$Integer`. A SEAM between two same-day commits, neither wrong alone: Track D's interface/implementation boundary taught the declaration tables which section a row came from, while FindSpecialization -- a visibility check whose own comment explains why it must be one -- still had only the UNIT half. It saw the unit's private row and skipped the program's declaration as an exact re-statement; FindUClass refused that same row. One declaration, two visibility checks, disagreeing. Specializations[] gained the section stamp (SpecDeclImpl[] + IMPLTAB_SPEC) and FindSpecialization now uses DeclVisibleSect."
---

# A specialization minted in a unit's implementation blocked the importer's own

Filed as a record rather than as work: found, diagnosed and fixed inside one
session, and it is on origin for a few hours between two commits. It gets a
ticket instead of a bare logbook line because **the code comments explaining
three separate edits name it**, and because the failure mode is one anybody
adding a ninth declaration table can repeat.

## Repro

`ugimpa` declares `TBox<T>` in its interface. `ugimpb` specializes
`TBox<Integer>` from an IMPLEMENTATION `uses` and publishes only an Integer. A
program then uses both and writes `var b: TBox<Integer>`.

```
pascal26:3: error: unknown type: TBox$Integer
```

FPC 3.2.2 and the pinned binary both print `42 202 4`.

## The seam

Two commits landed the same afternoon and neither is wrong:

- Track D's `84ea8e470` stamped every declaration table with the section its
  rows were declared in, so `FindUClass` correctly refuses `ugimpb`'s private
  `TBox$Integer` class row to an importer.
- This slice's `01998adb8` taught `ParseSpecialization` that "an exact
  re-statement is a no-op" is a question about the TEMPLATE INDEX, not a
  template name.

What broke is the check between them. `FindSpecialization` asks
`DeclVisible(SpecUnitIdx[i])` — the UNIT half of the answer and not the section
half — so:

| check | verdict on `ugimpb`'s private row |
| --- | --- |
| `FindSpecialization` | visible → "exact re-statement, skip the declaration" |
| `FindUClass` | not visible → `unknown type` |

The permissive check **suppressed the work the strict check then demanded**, so
the program's own declaration was never emitted. That is worse than either rule
applied alone, and it is the general shape: *a visibility question answered in
two places will eventually be answered two ways.*

## Fix

`Specializations[]` gained `SpecDeclImpl[]`, stamped from `DeclInImplNow` at
registration exactly as the other eight tables are, plus an `IMPLTAB_SPEC` tag
so `p.implleak` names the right row. `FindSpecialization` calls
`DeclVisibleSect`. `ImplPrivateApplies` treats the new tag like `IMPLTAB_UCLS`
— a minted specialization name has no builtin chain to outrank, so the ambient
exemption applies to it, which is the right answer for the same reason it is
right for a class.

## Measured

| | `42 202 4`? |
| --- | --- |
| fpc 3.2.2 | yes |
| pin `c31d03b202da` (predates both commits) | yes |
| origin with `84ea8e470`, before this fix | **no — `unknown type: TBox$Integer`** |
| after this fix | yes |

Test: `test/test_generic_implsect_dup.pas` + `generic_implsect_units/`.

## The other thing this run turned up, filed separately

frankD asked for the one case they had no coverage for: a generic TEMPLATE
declared in a unit's implementation section, named by an importer. **pxx accepts
it and FPC refuses it**, and the pinned binary accepts it too — pre-existing, not
fallout from the boundary work, because `Templates[]` is a token-arena registry
with no unit or section channel for a visibility answer to live in.
[[bug-p-a-generic-template-declared-in-a-units-implementation-is-visible-to-its-importers]],
prio 35.
