---
slug: bug-p-a-variant-refuses-wide-chars-and-interfaces
title: A Variant refuses WideChar, UCS4Char and an interface ("Variant := this type not yet supported")
track: P
prio: 40
type: bug
blocked-by: []
status: done
owner: opus5-frank1
created: 2026-08-24
summary: "`v := wc` (WideChar), `v := u` (UCS4Char) and `v := ifc` (any interface) do not compile: `Variant := this type not yet supported`. fpc 3.2.2 accepts all three, and pxx already accepts every neighbouring kind — Char, ShortString, Single, Currency — so this is a hole in one enumeration, not a design position. Present on `pinned` as well as HEAD."
---

# Symptom

```
pascal26:4: error: Variant := this type not yet supported
```

for three source types a Variant should hold. Measured 2026-08-24, `fpc 3.2.2
-Mobjfpc -O1` vs `stable_linux_amd64/default/pinned` and `compiler/pascal26` at
HEAD — pinned and HEAD are identical, so this predates the assignment
type-check work; it was found *by* it, not caused by it.

| `v := x` where `x` is | fpc | pxx |
| --- | --- | --- |
| `Char` | ACCEPT | ACCEPT |
| `WideChar` | ACCEPT | **REJECT** |
| `UCS4Char` | ACCEPT | **REJECT** |
| `ShortString` | ACCEPT | ACCEPT |
| `Single` | ACCEPT | ACCEPT |
| `Currency` | ACCEPT | ACCEPT |
| an interface (`IIntf`) | ACCEPT | **REJECT** |

# Repro

```pascal
program v3;
{$mode objfpc}{$H+}
type IIntf = interface ['{11111111-2222-3333-4444-555555555555}'] procedure Q; end;
var v: Variant; wc: WideChar; u: UCS4Char; ifc: IIntf;
begin
  v := wc;   { pascal26: Variant := this type not yet supported }
  v := u;    { same }
  v := ifc;  { same }
end.
```

# Why it is prio 30 and not urgent

It is honest: it refuses rather than miscompiling. Nothing silently produces a
wrong value here. It is filed because the `Variant := <scalar>` lowering
enumerates the kinds it accepts, and an enumeration that grew a hole once will
grow another.

# The fix, and the trap in it

Not three more `case` arms. `normalise-dont-special-case.md` applies literally:

- both wide character kinds are ORDINALS that fit the 8-byte Variant payload —
  route them through the same widening the `tyChar` arm already uses;
- an interface is a different matter, because it is REFCOUNTED and pxx spells it
  `tyRecord` (a 16-byte fat pointer {IMT, instance}). FPC stores it as
  `varUnknown` and takes a reference. Storing the fat pointer without the
  AddRef/Release pairing would trade this diagnostic for a use-after-free, so
  the interface half is the real work and should not be bundled with the two
  cheap character arms.

Splitting this ticket at that seam is reasonable; it is filed as one because
the enumeration is one place.

# Where

The `Variant := <scalar>` lowering in `compiler/ir.inc`; the message text
`'Variant := this type not yet supported'` is the anchor.

# Found by

The 625-pair fpc/pxx assignment cross-product built for
[[bug-p-an-assignment-is-not-type-checked-at-all]]. These two pairs are the
*entire* set of "fpc accepts, pxx refuses" in that matrix — everything else pxx
refuses, fpc refuses too.

# Outcome

The two wide-character kinds are fixed. The interface half is split off as
[[bug-p-a-variant-cannot-hold-an-interface]], at exactly the seam this ticket
named.

## The ticket's own suggested route was wrong, and measurement said so

"route them through the same widening the `tyChar` arm already uses" would
truncate. `VT_CHAR`'s payload is ONE BYTE (defs.inc), so `v := WideChar($20AC)`
would have come back as `#$AC` — trading an honest refusal for a silently wrong
value, which is strictly worse than the bug. Every character outside Latin-1
would have been destroyed, and nothing in the ticket's repro would have shown
it, because its repro used `WideChar` uninitialised.

What the two kinds actually are is documented in defs.inc: they "convert as
UTF-8". So the fix is the conversion every other string context already applies
to them — `WrapWideCharToUTF8` / `WrapUCS4ToUTF8`, both of which already existed
— applied at the assignment lowering when the target is a Variant. The store
then sees an ordinary `tyAnsiString` and needs no new tag, no new payload
encoding and no backend change at all.

Keyed on the KINDS, not on the `tyUInt16` heuristic the string arm next door
uses. That heuristic is sound there — assigning a Word to a string is
meaningless, so it can only have been a widechar — and unsound here, because
`v := someWord` is a perfectly ordinary number. The test pins `v := Word(65)`
staying `65` for exactly that reason.

## Wider than expected, and measured rather than assumed

The single site also fixed the record-field, array-element and by-value
parameter forms; all three are pinned in the test.

## Oracle, stated exactly

fpc 3.2.2's ACCEPTANCE of all three source types is what this ticket measured on
2026-08-24 and it stands. Its printed OUTPUT could not be diffed here: `uses
Variants` does not resolve on this box even with `-Fu` pointed at a present,
version-correct `variants.ppu`, so no fpc binary that prints a Variant can be
built. The expected values come from pxx's own documented UTF-8 rule for these
kinds. The test header says so rather than claiming an fpc diff it does not
have.

While checking that, `test/test_method_arg_typecheck_ok.pas` turned out to
carry the same overstatement from earlier today — its header said "Oracled
against fpc 3.2.2" when only its first six rows can be, fpc dying at RTE 217
after them (which IS measured, and is why its `uses Variants` is there).
Corrected in place.

## Gate

`test/test_variant_widechar_store.pas` (+ `.expected`) in `test-core`: the
euro and emoji rows are the ones a byte-wide slot would have destroyed, and the
Word rows guard the other side. Self-host byte-identical. pascal-conformance
346/0/170/34 and fgl 7/7 unchanged. `gate.sh quick` GREEN.


## Log
- 2026-08-26 — resolved, commit PENDING-COMMIT.
