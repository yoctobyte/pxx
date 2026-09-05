---
slug: decide-how-a-type-carries-an-identity-its-kind-cannot-hold
title: "How a type carries an identity its TTypeKind cannot hold: a new kind trio, or the enum's side-channel pattern generalised"
track: U
prio: 55
type: decide
blocked-by: []
status: open
owner: ""
created: 2026-09-05
summary: "Two open bug families have ONE cause: a type whose LAYOUT is an existing kind but whose SEMANTICS are not. ByteBool/WordBool/LongBool are tyUInt8/tyUInt16/tyInteger so their C-ABI width is right, and nothing downstream can tell them from integers -- so `if a` and `if not a` BOTH fire (p55), WriteLn prints 1 for TRUE, and Ord answers 1 where fpc answers -1. Separately an alias to an enum, and a set's char element, drop their identity the same way (p40). The fork: (A) give the sized booleans distinct TTypeKinds, which touches defs.inc's kind numbering -- the ONE thing CLAUDE.md says to coordinate by message rather than edit; or (B) generalise the pattern an enum already uses (tyInteger PLUS an id) into a side channel carried through symbols, fields, params and the alias table, which closes BOTH families in one move. Recommendation: B. Filed before any code because picking wrong makes the other family wider, not just later."
---

# Decide: how does a type carry an identity its kind cannot hold?

## The fork

Some types have the LAYOUT of an existing `TTypeKind` and different SEMANTICS.
Today the kind is all that survives a declaration, so the semantics are lost at
the first registration boundary and every consumer downstream sees the layout
type. Two bug families, one cause.

**A `ByteBool` is a `tyUInt8`.** That is deliberate and the width is right —
`pasparser_lval.inc` says so at the mapping:

> *"FPC's sized booleans are C-ABI booleans — a fixed-width integer where
> nonzero means true. They must keep their WIDTH (LongBool 4, WordBool 2,
> ByteBool 1); mapping them onto tyBoolean would silently resize any struct or
> call that crosses to C."*

The reasoning is sound and the widths match fpc 3.2.2 exactly. But that comment
weighed **two** options — map to `tyBoolean` and lose the width, or map to an
integer and keep it — and there is a third, which is this decision.

**An enum ALREADY uses the third option.** An enum is not a `TTypeKind` in this
dialect: an enum symbol is `tyInteger` with `SymEnumId >= 0`, and `CEEnumId`'s
own declaration in `defs.inc` states the convention. Layout in the kind,
identity beside it. It works — a direct enum variable prints its member name.
It just was never generalised, and it is incomplete even for enums: the alias
table has no column for the id, so a variable declared through `type TDays = D`
prints `1` where fpc prints `tue`.

## What each arm costs

**A. Distinct kinds** — `tyByteBool`, `tyWordBool`, `tyLongBool` (and
`tyQWordBool`).

- Every `case tk of` in the tree must gain the arms, and the ones that do not
  are silent wrong answers rather than compile errors — the failure mode this
  repo already knows from `TypeIsAnyString`, whose header states that a guard
  meaning "is this a string" must NOT enumerate kinds.
- It touches `TTypeKind` numbering in `defs.inc`. CLAUDE.md names token/node
  numbering in `lexer.inc`/`defs.inc` as **the one thing to coordinate by
  message** rather than edit, so this arm has a process cost before it has a
  code cost.
- It fixes the booleans and does **nothing** for the enum-identity family.
- It is the arm that makes `SizeOf` and struct layout obviously right, because
  the width is in the kind rather than beside it.

**B. Generalise the side channel** — a "semantic identity" carried next to the
kind, the way `SymEnumId` already is, through symbols, record fields, params,
return types and the alias table.

- Closes **both** families in one move: sized booleans get their `not`, their
  `WriteLn` and their `Ord`; enum aliases and set elements get their identity.
- The carry sites are already enumerated and already have precedent —
  `RegisterGeneralAlias` reads `LastType*` channels for a pointer's pointee, a
  string capacity, a file element width, a managed-string element width and
  (since 2026-09-05) a subrange's bounds. This is one more of the same, not a
  new mechanism.
- The risk is the one those channels already have and document: a channel is
  valid only in the window right after the parse that filled it, and a reader
  outside that window gets whatever the last unrelated declaration left behind.
  Every existing channel comment says this; the fix is the same discipline, at
  more sites.
- It does not make the width wrong: layout stays in the kind, which is what the
  original decision was protecting.

## Recommendation

**B.** The multiplier decides it: one mechanism closes two families, and the
pattern is not new here — it is the one enums already use, finished. Arm A is
also the one with the coordination cost and the enumerate-the-kinds failure
mode this repo has been bitten by before.

The honest argument for A is that a side channel that must be carried through N
sites will be forgotten at site N+1, and the forgetting is silent. That is real,
and it is why B should land with the carry sites listed in one place and a test
that reads the identity back through **each** of them — a variable, a record
field, a parameter, a return type and an alias — rather than through whichever
one was convenient.

## What it would close

- [[bug-p-a-sized-boolean-is-true-and-not-true-at-the-same-time]] (p55) — `if a`
  and `if not a` both firing is a compiling program taking both branches with no
  diagnostic, in exactly the types an FPC binding to a C library declares.
- [[bug-p-a-type-alias-drops-the-enum-identity-and-a-set-drops-its-char-element-kind]]
  (p40).
- `QWordBool`, which does not exist at all and is deliberately not being added
  until this is settled: a fourth member of a family whose `not` is broken is
  not progress, and adding it first makes the eventual fix wider.

## Why this is filed rather than built

Picking wrong does not merely delay the other family — it makes it **wider**.
Arm A leaves the enum-identity work entirely undone and adds kind arms that the
enum work would then not use; arm B done narrowly (booleans only) builds the
channel and then has to be revisited to thread it through the alias table
anyway. The cheap moment to choose is before either line is written.

Both bugs are pre-existing on pin v403; neither is a regression, so nothing is
burning.
