---
slug: bug-p-a-cast-to-an-array-type-is-not-recognised
title: "`TArr(x)` — a cast to a named ARRAY type — is `undefined variable`, and arrays are the only kind missing"
track: P
prio: 40
type: bug
status: backlog
found: 2026-09-04
found-by: frankA
owner: ""
blocked-by: []
summary: "A cast to a named ARRAY type is not recognised at all: `TArr(aa)[1]` gives `undefined variable (TArr)` where fpc 3.2.2 compiles it. Swept every type kind a named cast can target and arrays are the ONLY gap — record, string alias, pointer alias, class, integer alias, enum, set and procedural type all work. The cast dispatch consults FindTypeAlias (plus the lazy builtin-pointer names) and never FindArrayType, which the SizeOf path two hundred lines away does consult. Not a postfix bug: the name never resolves, so it fails before any suffix is considered."
---

# A cast to a named array type is not recognised

Found while tabulating which primaries can head a postfix chain
(`refactor-p-three-hand-rolled-postfix-loops`). It is not a postfix gap — the
cast itself does not resolve — but it turned up as a row in that table and
belongs with that group.

## Measured — binary `f8b9e4394673`, oracle fpc 3.2.2

Every kind a named type cast can target, each `TName(v)` followed by whatever
postfix that kind admits:

| cast target | kind | pxx | fpc |
| --- | --- | --- | --- |
| `TRek(r).a` | record | ok | ok |
| `TStrA(ss)[1]` | string alias | ok | ok |
| `PArr(rawp)^[1]` | pointer alias | ok | ok |
| `TDeriv(bb).fV` | class | ok | ok |
| `TIntA(ii)` | integer alias | ok | ok |
| `TEnum(1)` | enum | ok | ok |
| `TSet(st)` | set | ok | ok |
| `TProcT(@PZ)` | procedural | ok | ok |
| `TArr(aa)[1]` | **static array** | **`undefined variable (TArr)`** | `10` |
| `TCharA(ca)[1]` | **array of Char** | **`undefined variable (TCharA)`** | `b` |
| `TDyn(dy)[1]` | **dynamic array** | **`undefined variable (TDyn)`** | `10` |

All three array flavours fail, in all four syntactic contexts (assignment RHS,
parenthesised, argument, inside `and`). **Eight kinds work and one does not**,
which is what makes this a gap rather than a design position.

The diagnostic is `undefined variable`, so the name is not being resolved as a
type at all — nothing about a suffix, and `var aa: TArr` obviously works, so the
type exists.

## The lead

`FindArrayType(name)` exists and is already consulted for exactly this reason
elsewhere in the same file — `pasparser_expr.inc:3900` and `:3936` ask it for
`SizeOf`, with a comment saying it *"mirrors ParseVarSection's FindArrayType
check ... so it must be tried here too, ahead of FindTypeAlias"*. The cast arms
ask `FindTypeAlias` and then `EnsureBuiltinPtrAlias`, and never ask
`FindArrayType`.

**Do not fix this by adding a sixth door.**
[[refactor-p-five-dispatch-sites-for-one-named-type-cast]] is exactly this
subject: five places decide what `SomeName(expr)` casts to and *"differ only in
which names they recognise"*, and its history is four rounds of one door being
taught something the next door still did not know. An array arm added to
whichever door is convenient is round five. That refactor says the recognition
rules should merge into one resolver — this is a concrete, currently-broken
input for it, and it is probably the ticket that justifies doing it.

Note the ORDER constraint that refactor records and that applies here too:
`FindTypeAlias` must be consulted first, because a source declaration outranks a
builtin (`symtab.inc:6215`).

## Gate

The table above re-run against fpc 3.2.2, plus a row asserting a cast to an
array type of a DIFFERENT extent than the source is either handled or refused
deliberately — FPC allows a same-size reinterpret and that boundary is not
measured here.
