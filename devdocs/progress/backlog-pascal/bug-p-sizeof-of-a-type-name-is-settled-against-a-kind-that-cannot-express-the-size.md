---
slug: bug-p-sizeof-of-a-type-name-is-settled-against-a-kind-that-cannot-express-the-size
track: P
prio: 45
type: bug
status: new
owner: ""
blocked-by: []
summary: "Five builtin type names accept `var v: N` and reject `SizeOf(N)` with 'unknown type or variable': ShortString, PChar, PAnsiChar, PWideChar, TextFile. Split out of bug-p-sizeof-rejects-twelve-type-names (closed -- both INSTANCES of its ordering pattern are fixed, this is its residue and a different defect). NOT reachable by any further ordering fix: 582e4de09's fallback is `TypeSize(KIND)`, and no TTypeKind carries ShortString's 263 bytes or TextFile's 4128 -- the declaration side gets all five right because it resolves a TYPE. umbrella-sizeof-is-one-answer shape 1, on the Pascal side. DO NOT copy the declaration arms into SizeOf: that is the fourth instance of a drift BuiltinTypeNameTk's header already records three times, and TextFile settles it anyway since it needs IsRecordType('text'), which a width table cannot express. DO NOT fix toward FPC's 256/888 -- 263 and 4128 are correct about OUR storage. The carrier already exists: SizeOfSlot(tyFixedString, DEFAULT_STR_CAP) is exactly 263; what is missing is that the NAME never reaches a sizing call."
---

# `SizeOf(<type name>)` is settled against a KIND that cannot express the size

Split from [[bug-p-sizeof-rejects-twelve-type-names-that-a-declaration-accepts]]
on 2026-09-02, at the coordinator's routing call. That ticket's pattern — a
builtin type name settled against the builtin TABLE rather than against the
PROGRAM — had two instances and both are now fixed (`582e4de09` for SizeOf,
`2ba37ba91` for ParseTypeKind). **This is what is left, and it is a different
defect**: not an ordering question at all.

It is split rather than left as residue because a ticket titled "twelve type
names" whose twelve names are resolved reads as done, and the newest finding
should not sit in the least-read position of a closed-looking ticket.

## Measured 2026-09-02, by two instruments that fail differently

| name | `var v: N` | `SizeOf(N)` |
| --- | --- | --- |
| ShortString | accepted, **263** | rejected |
| PChar, PAnsiChar, PWideChar | accepted, **8** | rejected |
| TextFile | accepted, **4128** | rejected |

`SizeOf: unknown type or variable` in every case — the same no-diagnostic shape
`BuiltinTypeNameTk`'s header says it was created to end.

Identical on the **pinned** binary `766b99f98` (v401), which POSTDATES
`582e4de09`, so none of it is a regression from the recent work.

**Corroborated, and the corroboration counts**, because the two readings cannot
go wrong the same way: frankC read `SizeOf(v)` of a declared variable, and
frankb-a9 read the physical element **stride** of an array (`@a[1] - @a[0]`) —
deliberately not using `SizeOf`, since `SizeOf` is the operator under repair and
validating it with itself is the trap. Same five numbers.

## Why no further ordering fix reaches them

`582e4de09` added the fallback for exactly this shape — a name demoted from
builtin and then unresolved must come back to the builtin answer — and wrote:

```pascal
if szBTkAny <> tyUnknown then prevTok := TypeSize(szBTkAny)
```

**That fallback takes a KIND.** `ShortString` is 263 bytes and `TextFile` is
4128; no `TTypeKind` carries a capacity or a record layout, so there is no value
`szBTkAny` could hold that produces them. The declaration side answers all five
correctly *because it resolves a TYPE*.

That is `umbrella-sizeof-is-one-answer` shape 1 stated on its own residue: the
oracle takes too few parameters, so a type whose size is not a function of its
kind cannot be answered at all.

## Do not

**Do not copy the declaration arms into SizeOf.** They are the `textfile`,
`shortstring`, `pchar`/`pansichar` and `pwidechar` arms in `ParseTypeKind`
(`pasparser_decl.inc`; cited by content because they moved ~21 lines in
`2ba37ba91` and a stale line number does not error, it points somewhere). Each
sets something a kind cannot carry — `LastTypeStrCap`, `LastTypeRecId`,
`LastTypePointerElemTk` — which is precisely why `BuiltinTypeNameTk`'s header
restricts the shared table to side-effect-free names. **These five are the names
that break that rule**, so copying the arms would be the fourth instance of a
drift that header already records three times (`Real`, bare `string`,
`Extended`), bought with a green tick today.

`TextFile` settles it independently of the argument: it resolves through
`IsRecordType('text')`, so even a width table would not be enough.

**Do not fix toward FPC's numbers.** FPC says 256 for `ShortString` and 888 for
`TextFile`. Ours are 263 and 4128 and are **correct about our own storage** —
`ShortString` maps here to a 255-cap `tyFixedString` with an 8-byte length word.
Reaching for the oracle first is the obvious wrong move, and it is the same
distinction the `string[N]` work turned on. Per CLAUDE.md we are on par with the
LANGUAGE, not with FPC.

## The lead

**The carrier already exists.** `SizeOfSlot(tyFixedString, DEFAULT_STR_CAP)` is
exactly 263 (`DEFAULT_STR_CAP = 255`, `defs.inc`). What is missing is that the
NAME never reaches a sizing call that takes a capacity — `SizeOf(<name>)`
resolves through a kind and stops.

So the direction is for `SizeOf(name)` to resolve the name the way a
DECLARATION does and size the resulting type, rather than to grow another
name→width table. Adding one would be the fifth oracle the umbrella exists to
prevent.

## Wiring

Add to `umbrella-sizeof-is-one-answer`'s `blocked-by`. It is the same sentence
as the C members closed on 2026-09-02 and as frankb-a9's `string[N]` work:
something other than the layout engine was asked how big a type is, and it
answered — or here, could not, and said "unknown type".
