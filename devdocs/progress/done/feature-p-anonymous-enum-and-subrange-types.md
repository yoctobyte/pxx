---
track: P
prio: 40
type: feature
blocked-by: []
status: done
owner: claude-A
commit: 3d521d909
summary: "`var c: (red, green, blue)` and `var n: 1..5` were `unknown type` — the enum member-list and the lo..hi grammars lived only in ParseTypeSection's NAMING path, so the same construct worked with a name in front of it and not without. ParseTypeKind already had anonymous arms for record, procedural, pointer, array and set; these were the two missing."
---

# Anonymous enum and subrange types are not accepted

Found 2026-08-22 while probing `Low`/`High`
([[bug-a-low-high-of-an-ordinal-variable-answer-0-and-minus-1]]) — the probe
program would not compile because it declared `var e: (eA, eB, eC)`.

## The measurement

`fpc -Mobjfpc -O1` 3.2.2 vs pxx `fa549a775`. Each row is a declaration.

| declaration | fpc | pxx before |
| --- | --- | --- |
| `var e: (eA, eB, eC)` | ok | **`unknown type`** |
| `var s: 1..5` | ok | **`unknown type`** |
| `var c: 'a'..'z'` | ok | **`unknown type: a`** |
| `var v: record f: 1..5; end` | ok | **error** |
| `type TR = record f: (a, b); end` | ok | **error** |
| `var a: array[0..2] of 1..5` | ok | **error** |
| `type T = array[1..3] of (a, b)` | ok | **error** |
| `procedure P(x: 1..5)` | **rejected** | rejected (agrees) |
| `var a: array[0..2] of Integer` | ok | ok |
| `var r: record x: Integer; end` | ok | ok |
| `var p: ^Integer` | ok | ok |
| `var st: set of Byte` | ok | ok |
| `var f: function(x: Integer): Integer` | ok | ok |

The bottom five are the point: `ParseTypeKind` already accepted an anonymous
record, procedural type, pointer, array and set. Enum and subrange were the two
forms nobody had reached for.

## Root cause

Both grammars existed, in `ParseTypeSection`, behind a name. `T = (a, b)` parsed
a member list with explicit ordinals, holes and `{$SCOPEDENUMS}`; `T = lo..hi`
parsed two `ConstEval`s and retained the bounds for `{$R+}`. Neither was
reachable from `ParseTypeKind`, which is what every *use* of a type goes
through. So the feature was half-present in the way
`devdocs/dev/normalise-dont-special-case.md` describes: one concept, two
spellings, and only the spelling someone had needed was wired up.

The named subrange path even carries the comment *"same treatment as an inline
`var x: lo..hi` subrange"* — which was aspirational. There was no inline form.

## The fix

- **`ParseEnumMembers(etid)`** lifted out of `ParseTypeSection` — CurTok on `(`
  at entry, past `)` at exit. The named path now calls it, so there is one
  member-list grammar rather than two. An enum with explicit ordinals, holes
  and scoping is not something to keep a second copy of.
- **`tkLParen` arm in `ParseTypeKind`**: mint an unnamed enum
  (`RegisterEnumType(0, 0)`, the `AddUClass(0, 0)` precedent the anonymous
  record arm already uses), parse the members through the shared routine, hand
  back the same `tyInteger` + `LastTypeEnumId` the named form produces.
  Scoping is off by definition — `{$SCOPEDENUMS}` makes members reachable only
  as `TName.member`, and there is no `TName`.
- **`tkInteger, tkMinus, tkString` arm**: `ConstEval .. ConstEval`, base type
  `tyChar` for a char-literal bound and `tyInteger` otherwise, bounds retained
  in `LastTypeIsSub`/`LastTypeSubLo`/`LastTypeSubHi` exactly as the named form
  does — so `{$R+}` checks stores against them and `Low`/`High` answer the
  subrange rather than the base type.

Because both arms produce the same `LastType*` state the named forms produce,
every consumer — `AllocVar`, the record-field walker, the array-element path —
needed no change at all. That is the test of whether an anonymous arm is in the
right place.

## Verified against fpc

Value, ordering, comparison and `Low`/`High` for an anonymous enum; explicit
ordinals (`(hx = 10, hy, hz = 20)` giving 10, 11, 20); an integer subrange, a
negative-low subrange and a char subrange with their own bounds; all four as
record-field and array-element types; and `for i := Low(n) to High(n)` running
the right number of times. Byte-identical to `fpc -O1` on the same source
except one row.

That row is `SizeOf(n)` for a subrange: 4 here, 1 in fpc, because our subranges
are stored at the base type's width — `compat-pascal-subrange-storage-size`,
unrelated to this ticket. Asserted at the pxx value so a change to *that* rule
surfaces here rather than drifting.

## Gate

`make compiler/pascal26` (self-host fixedpoint) + `tools/gate.sh quick` GREEN.
Test `test/test_anonymous_enum_and_subrange_types.pas`, 24 assertions, wired
into `test-core`.
