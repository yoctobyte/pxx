---
slug: refactor-p-the-field-declaration-parser-exists-twice
title: "A record's field-declaration parser and a class's are two copies of the same 120 lines"
track: P
prio: 30
type: refactor
blocked-by: []
status: backlog_new
owner: ""
created: 2026-08-25
summary: "`ParseRecordFields` (pasparser_decl.inc ~3199) and the class-body field arm inside `ParseTypeSection` (~4824) parse the same grammar — comma-separated names, inline fixed/dynamic array, named array alias, scalar — with the same locals under different names and the same AddUField tail. Every field-level feature has to be written twice, and the second copy is the one that stays broken."
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
