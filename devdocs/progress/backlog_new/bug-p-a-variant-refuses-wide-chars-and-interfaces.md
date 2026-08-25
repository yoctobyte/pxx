---
slug: bug-p-a-variant-refuses-wide-chars-and-interfaces
title: A Variant refuses WideChar, UCS4Char and an interface ("Variant := this type not yet supported")
track: P
prio: 40
type: bug
blocked-by: []
status: backlog_new
owner: ""
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
