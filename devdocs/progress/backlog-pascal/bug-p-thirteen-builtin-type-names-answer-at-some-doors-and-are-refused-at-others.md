---
track: P
prio: 35
type: bug
blocked-by: []
summary: "TEN of an original thirteen builtin type names are accepted at some doors and refused at others while fpc 3.2.2 accepts them everywhere: `High`/`Low` of ByteBool, LongBool and WordBool; `Low` of AnsiString, RawByteString, UnicodeString, UTF8String and WideString; and a cast to Variant/OleVariant stored in its declared type. Every one DECLARES fine, casts fine and answers SizeOf, so nothing about the name looks broken from any single door. WideChar, UnicodeChar and UCS4Char were the same shape and are FIXED — `OrdinalTypeBound` had no arm for the two character kinds carved out of integer kinds. Found by asking every name at every door (`tools/type_name_every_door_probe.py`), not by a failing program."
status: new
owner: ""
---

# One name, several doors, and the working ones vouch for the broken ones

The Pascal frontend recognises a builtin type NAME at several independent
places — the declaration path, the cast doors, `SizeOf`, `High`/`Low`,
`TypeInfo` — each with its own recognition rule. The expensive failure is not
two doors disagreeing about a VALUE. It is one name working at some doors and
being refused at others, because **every working door tells you the name is
fine**, and a name with synonyms hides it completely: `SizeUInt` cast and
`SizeOf`d correctly for months while `High(SizeUInt)` said *undefined variable*,
and its three synonyms `SizeInt` / `NativeUInt` / `PtrUInt` all worked
(`ecb00083e`).

Measured at `1df943481` over all 51 names in the union of `OrdinalNameToTk` and
`BuiltinScalarTypeKind`, `{$mode delphi}`, both compilers, seven doors each
(declaration, `SizeOf(T)`, a cast stored in its DECLARED type, the cast's value,
`High`, `Low`, `TypeInfo`) — 314 cells agree, 23 differ:

| name(s) | refused at | fpc 3.2.2 answers |
| --- | --- | --- |
| ~~`WideChar` `UnicodeChar` `UCS4Char`~~ | ~~`High` `Low`~~ | **FIXED** — see below |
| `ByteBool` `LongBool` `WordBool` | `High` `Low` | `TRUE` / `FALSE` |
| `AnsiString` `RawByteString` `UnicodeString` `UTF8String` `WideString` | `Low` | `1` |
| `Variant` `OleVariant` | the cast (`x := Variant(y)`) | accepts |

**The sized booleans are the interesting one and they are NOT a one-liner.**
They map to `tyUInt8` / `tyInteger` / `tyUInt16` on purpose, to keep their C-ABI
WIDTH, and `High`/`Low` read that kind — so simply teaching `OrdinalNameToTk`
about them would answer `High(LongBool) = 2147483647` instead of `TRUE`. They
need a kind that carries a width AND boolean bounds, which the current table
cannot express. Measured before rejecting the delegation, not after.

**The string `Low` rows are probably one fix**, and `High` already works for
all five, so whatever answers `High` has the name and declines the sibling.

**Not filed as five tickets** because the shape is one: a per-door recognition
rule that was correct for the names its own tests used. Whoever takes this
should run the probe first — it is the only instrument that can see the class,
since a per-door test passes on every door that works.

## Guard

`tools/type_name_every_door_probe.py`, indexed in
`devdocs/dev/differential-probes.md`. Both controls are branched on:
`zzznosuchtype` must be refused at every door by both compilers, and `integer`
accepted at every door by both. Without the first, a probe where every program
fails to build reports a clean agreement on every row.

**`{$mode delphi}` is load-bearing in that probe and it is why the first run was
wrong.** Without a mode directive fpc compiles in mode `fpc`, where `Integer` is
a SMALLINT — the first run reported `SizeOf(Integer)` as `4|2` and
`High(Integer)` as `2147483647|32767` and they read as three defects. They were
one missing line, and the oracle was answering honestly about a different type
than the one pxx means.

## Related

- `refactor-p-five-dispatch-sites-for-one-named-type-cast` — the same subsystem
  from the CAST side. This ticket is the other half: that one is about several
  doors for one operation, this one about one name across several operations.
- `bug-a-the-builtin-type-name-table-exists-twice-and-the-two-disagree` — the
  ancestor. The two tables no longer disagree on a shared name (measured); they
  differ only by which names each HAS, which is what produces these rows.


## 2026-09-06 (frankA) — three of the thirteen were one missing case arm

`OrdinalTypeBound` (`pasparser_lval.inc`) folds `High`/`Low` of a builtin
ordinal, as a `case` over kinds. It had `tyChar` and `tyUInt16` and **no
`tyWideChar` or `tyUCS4Char`** — and returning False there is read by
`TryFoldHighLowType` as *"not an ordinal type NAME at all"*, so it fell through
to the variable path and reported `undefined variable (WideChar)`. The name was
recognised by `OrdinalNameToTk` and discarded one call later.

**The case was COMPLETE when it was written.** A `WideChar` variable was
`tyUInt16` then — which is listed, and 65535 is `tyUInt16`'s right answer — and
a `UCS4Char` was a 32-bit integer kind. The fix that gave each its own kind took
it out of this case without editing it, and the case still reads as correct.
Third and fourth instance of that in one session; the two others were
`IRVariantUnboxKind` and ir.inc's variant-unbox helper dispatch (`a3933d0f7`).

`High(UCS4Char)` is **1114111** (`$10FFFF`, the largest Unicode code POINT),
which is fpc's answer and NOT the 4294967295 that deriving the bound from its
4-byte storage would give. Asserted deliberately: a row whose expected value
equals what the machinery would produce by doing nothing cannot fail.

Test `test/test_high_low_of_the_carved_out_char_kinds.pas`, `.expected` from
fpc, with `Char`/`Word` control rows through the same case and the const-fold
path pinned beside the expression one (they are documented as changing
together). Positive control is pin v404, which fails with
`High/Low in a constant expression: expected an ordinal type name`.

**Ten left, and the sized booleans are still the hard one** — they need a kind
carrying a width AND boolean bounds, which no current table can express.
