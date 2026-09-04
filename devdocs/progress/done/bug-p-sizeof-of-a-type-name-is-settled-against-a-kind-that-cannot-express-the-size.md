---
slug: bug-p-sizeof-of-a-type-name-is-settled-against-a-kind-that-cannot-express-the-size
track: P
prio: 45
type: bug
status: done
owner: ""
blocked-by: []
summary: "FIXED 2026-09-04. All five names size now: SizeOf(N) = SizeOf(var of N) for ShortString, PChar, PAnsiChar, PWideChar and TextFile, on x86-64 and on i386/aarch64/arm32/riscv32. SizeOf re-parses such a name through ParseTypeKind and sizes what comes back rather than settling it against a TTypeKind; `BuiltinTypeNameNeedsDecl` holds NAMES, never widths, so the declaration arms stay the only place a width is decided and the fifth oracle this ticket forbids was not built. TWO OF THIS BODY'S OWN NUMBERS WERE STALE BY THE TIME IT WAS WORKED and the correction is the more useful half: it said ShortString is 263 and `DO NOT fix toward FPC's 256`. It is 256, and 256 is OURS -- `string[255]` has been 256 since the phase-4 flip `fd186a975`, and ShortString is that same type. The ticket was right that reaching for the oracle first is the wrong move, and wrong that the oracle disagreed. TextFile stays 4128 against FPC's 888, correctly, and only relations are asserted for it. FOUND WHILE MEASURING IT, AND BIGGER THAN IT: the flip moved the `string[N]` arm and not the `shortstring` arm nine lines below, so ONE Pascal type had TWO layouts -- 264 bytes with data at offset 8 against 256 with data at offset 1, in one program. Values agreed everywhere the compiler COPIED, so it read green; a `var` parameter ALIASES, and passing a `string[255]` to `var s: ShortString` printed Length = 122511465736197 from ordinary declared source with no diagnostic. A SIZE ROW CANNOT CATCH THAT: measured against a control compiler carrying only that revert, all nine size rows read OK while `spelling`, `layout` and `varparam` failed. Tests: `test_shortstring_is_string_255.pas` (default plus four cross), the five names added to `test_sizeof_builtin_type_names.pas`, and three shadow rows (`o 14 18 22`) added to its complement, because the delegation is a SECOND route into the builtin answer and needed its own proof that a user declaration still wins. Every transcript is FPC 3.2.2's, byte-identical. RESIDUAL, named rather than closed: a SIXTH such name added to ParseTypeKind and not to BuiltinTypeNameNeedsDecl is refused again -- a weaker mode than a drifting width, since it cannot produce a wrong NUMBER, only a rejection."
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

## Log
- 2026-09-04 — resolved; this names the commit that carried the resolve, which is not always the one that carried the change — commit 6a890a405.


## Resolved 2026-09-04 (frankh-15)

The lead in this body was right about the DIRECTION and stale about the
NUMBERS. Only the direction was load-bearing, so separating them is worth a
paragraph.

**Right, and it held:** do not copy the declaration arms in, and do not grow a
name-to-width table. The fix delegates to `ParseTypeKind` -- the declaration
resolver itself -- so a width changed in an arm is picked up with no edit at
the SizeOf site, and the only thing written down twice is a list of NAMES.
`PChar`/`PAnsiChar`/`PWideChar` are worth a note against this body's own
framing: their size IS expressible by a kind (pointer width). They failed not
because no kind carries the answer but because their ARM carries a pointee, so
the name never reached the shared table at all. Three of the five, not five.

**Stale:** `SizeOfSlot(tyFixedString, DEFAULT_STR_CAP)` is not 263 -- it
measured 264 before the flip -- and `do not fix toward FPC's 256` inverted
after it. This body was written before `fd186a975` and nothing updated it.

**Why that was not a footnote:** chasing the 263 is what surfaced the layout
split. `SizeOf(ShortString)` measured 264 where this ticket said 263, and
`SizeOf(string[255])` measured 256 -- two numbers for one Pascal type. A
number that is merely stale reads as noise; a number that is stale in a
direction nothing explains is a lead.
