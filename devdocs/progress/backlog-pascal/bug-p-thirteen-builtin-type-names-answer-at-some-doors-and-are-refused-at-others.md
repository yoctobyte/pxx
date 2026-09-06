---
track: P
prio: 35
type: bug
blocked-by: []
summary: "Thirteen builtin type names are accepted at some doors and refused at others while fpc 3.2.2 accepts them everywhere: `High`/`Low` of WideChar, UnicodeChar, UCS4Char, ByteBool, LongBool and WordBool; `Low` of AnsiString, RawByteString, UnicodeString, UTF8String and WideString; and a cast to Variant/OleVariant stored in its declared type. Every one DECLARES fine, casts fine and answers SizeOf, so nothing about the name looks broken from any single door. Found by asking every name at every door (`tools/type_name_every_door_probe.py`), not by a failing program."
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
| `WideChar` `UnicodeChar` `UCS4Char` | `High` `Low` | the code-unit bounds |
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
