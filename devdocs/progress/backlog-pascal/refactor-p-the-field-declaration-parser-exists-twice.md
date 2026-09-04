---
slug: refactor-p-the-field-declaration-parser-exists-twice
title: "The field-declaration parser exists THREE times -- record, class and variant part -- and the third is not in this ticket's slug"
track: P
prio: 55
type: refactor
blocked-by: []
status: backlog
owner: ""
created: 2026-08-25
summary: "THREE copies, not two, and the uncounted one had two SILENT defects (both fixed 2026-09-05; the lift is still open). `ParseRecordFields` (pasparser_decl.inc, now ~3840) and the class-body field arm inside `ParseTypeSection` (now ~6150) parse the same grammar — comma-separated names, inline fixed/dynamic array, named array alias, scalar — with the same locals under different names and the same AddUField tail. Every field-level feature has to be written twice, and the second copy is the one that stays broken."
---

# Measured, 2026-08-25

Threading the enum identity onto a field
(`bug-p-an-enum-reached-through-a-field-or-index-still-writes-its-ordinal`)
required the SAME six edits in both places: reset the capture beside
`isArr := False`, take it from `LastTypeEnumId` after each of the three
`ParseTypeKind` calls, take it from the alias registry in the two named-array
arms, and stamp it after `AddUField`. The two blocks differ only in indentation
and in the local's name (`fEnumId` vs `fEnumId2` — they are in different
routines, so they cannot even share one).

The arms line up one for one:

| | ParseRecordFields | ParseTypeSection's class arm |
| --- | --- | --- |
| names | `fldNOffs/fldNLens` loop | identical |
| `array[..] of T` | ~3238 | ~4861 |
| `array of T` (nested) | ~3254 | ~4879 |
| named dyn alias | ~3275 | ~4896 |
| named fixed alias | ~3292 | ~4910 |
| scalar | ~3318 | ~4934 |
| size/align | `if fIsDyn / tyString / tyFixedString / tyRecord` | identical |
| `AddUField` tail | ~3370 | ~4970 |

# Why it is a refactor ticket and not a bug

Nothing is wrong TODAY — the enum work put both copies in step. The cost is that
every future field-level attribute is two edits, and the failure mode is silent:
the feature works on records and not on classes (or the reverse), which reads as
a mysterious dialect gap rather than as a missing paste.
`devdocs/dev/normalise-dont-special-case.md` is exactly this shape, one level up
from the const-vs-variable cases it collects.

# Shape of the fix

Lift the block into one `ParseFieldDeclInto(ci: Integer; ...)` that both callers
invoke, with the visibility/`class var`/property/method dispatch staying where it
is — the duplication is only the part after `Expect(tkColon, ':')`. The class arm
carries a couple of extras (published/visibility stamping); those are already
applied AFTER the shared tail, so they survive the lift unchanged.

Gate: the usual `make compiler/pascal26` fixedpoint + `tools/gate.sh quick`. The
lift is a pure code move, so a byte-identical self-host is the strong evidence
here.

## Re-derived 2026-09-05 (frankB) — it is THREE, and the third had two live bugs

Re-counted before taking it, because every ticket census re-derived that night
was wrong. This one is wrong in the **opposite** direction from the usual, which
is the dangerous one: it UNDERCOUNTS.

```
$ grep -n 'UFldEnumId\[UFldCount-1\]' compiler/pasparser_decl.inc
4286  -> ParseRecordFields
6258  -> ParseTypeSection
$ grep -n 'AddUField(' compiler/pasparser_decl.inc     # by enclosing routine
3320, 3426, 3428, 3432  -> ParseRecordVariantPart      <-- the third copy
4279, 4281, 4285        -> ParseRecordFields
6251, 6253, 6257        -> ParseTypeSection
```

`ParseRecordVariantPart` parses branch fields with the same grammar and the same
`AddUField` tail, and it is not in this ticket. Its arms line up against the
other two like this:

| arm | RecordFields | class arm | **VariantPart** |
| --- | :-: | :-: | :-: |
| comma-separated names | yes | yes | yes |
| `array[..] of T` | yes | yes | yes |
| `array of T` (dynamic) | yes | yes | **no — and correct**, FPC refuses refcounted types in a variant part |
| named array alias | yes | yes | **NO — silent bug** |
| frozen string sizing | yes | yes | yes |
| `UFldEnumId` stamp | yes | yes | **NO — silent bug** |

**Both gaps were live, and both are fixed** (`ParseRecordVariantPart` now
captures `LastTypeEnumId` and has a named-fixed-array arm; multi-dim named
aliases are refused with a message rather than mis-sized, matching the inline
spelling that was already refused). Measured on pin v403 against fpc 3.2.2:

```
                       pin v403        pxx now / fpc
case 0: (c: TColor)    2               Blue
case 3: (ea: TEArr)    0 2             Red Blue
SizeOf(TVar)           8               20
```

The size row is the one that matters: with `TArr = array[0..3] of Integer` in a
branch, `ParseTypeKind` answered the ELEMENT kind, the field was sized as one
Integer, and `v.a[3] := 44` wrote twelve bytes past the end of the record. It
read back correctly, because the read went to the same wrong place — so every
VALUE row on the pin printed a plausible number.
`test/test_variant_part_field_arms.pas` pins all of it.

## This raises the ticket rather than closing it — 45 -> 55

The lift is NOT done; only the two divergences are. The ticket's own argument
was that the cost is future edits, "and the failure mode is silent". That is no
longer a prediction: it has now happened twice, in a copy the ticket did not
know about, and the drift runs **both ways** — the variant part's own comments
record it being right about frozen strings while the other two were wrong
(*"The variant-part arm a few hundred lines up already tested both kinds; this
one and its class sibling did not"*), and this pass found it wrong about two
things they were right about.

## Amendment to the shape of the fix

"Lift the block into one `ParseFieldDeclInto`" should be **three callers, not
two** — and the split is not where the ticket puts it. What all three share is
the part between `Expect(tkColon, ':')` and the size/align computation: the type
spec and what it yields (`fTk`, `fRec`, `fEnumId`, `isArr`, `arrLen`, `fIsDyn`,
`fDynDepth`, `fNDims`, the dimension table, `fStrCap`). What they do NOT share is
the offset bookkeeping: `ParseRecordVariantPart` resets to `branchFieldOff` per
branch and tracks `variantMax`, and its whole reason for existing is that
overlay. **Lift the spec parse and the sizing; leave the offsets alone.** A lift
that tries to unify the offset half will fight the variant part's overlay model
and is the version of this refactor that goes wrong.

