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
summary: "Two open bug families have ONE cause: a type whose LAYOUT is an existing kind but whose SEMANTICS are not. ByteBool/WordBool/LongBool are tyUInt8/tyUInt16/tyInteger so their C-ABI width is right, and nothing downstream can tell them from integers -- so `if a` and `if not a` BOTH fire (p55), WriteLn prints 1 for TRUE, and Ord answers 1 where fpc answers -1. Separately an alias to an enum, and a set's char element, drop their identity the same way (p40). The fork: (A) give the sized booleans distinct TTypeKinds, which touches defs.inc's kind numbering -- the ONE thing CLAUDE.md says to coordinate by message rather than edit; or (B) generalise the pattern an enum already uses (tyInteger PLUS an id) into a side channel carried through symbols, fields, params and the alias table, which closes BOTH families in one move. Recommendation: B. A costing of the Pascal-frontend arm is appended (frankB, 2026-09-05, compiler 47618f77c240) and DISPUTES the multiplier premise: the two families are independent, arm A has three in-tree precedents (tyBool8/tyUCS4Char/tyWideChar) that landed for +77..+144 and ~22 sites rather than the 565 feared, and tyWideChar is this same decision on a storable type taken the OTHER way because a node-level marker could not serve WriteLn. Choice still open with U."
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

---

## Costing the Pascal-frontend arm (frankB, 2026-09-05) — input, not an answer

Asked to cost arm B, which is the arm that lands in `pasparser_*.inc`. Every
number below is measured on compiler `47618f77c240`; the probes are in the
commit message. **I am not picking an arm** — but the costing does not support
the ticket's own recommendation, so it is written up as a recommendation with
the measurement attached, and the choice stays with U.

### 1. The read-site census — which shapes actually drop it

`if a` / `if not a`, one program, both compilers:

| shape | fpc 3.2.2 | pxx |
| --- | --- | --- |
| `var a: ByteBool` | `T.` | `TT` |
| record field `r.f` | `T.` | `TT` |
| array element `arr[0]` | `T.` | `TT` |
| function result `Mk(True)` | `T.` | `TT` |
| `var l: LongBool` | `T.` | `TT` |
| **`a and c`** | `.T` | **`.T`** |
| **`a = c`** | `.T` | **`.T`** |
| `WriteLn(a, l)` | `TRUE TRUE` | `1 1` |
| `Ord(a), Ord(l)` | `-1 -1` | `1 1` |

**The last two rows of the operator group already match.** The identity does NOT
need to propagate through `and`/`or`/`=` — those operators yield a real
`tyBoolean` and are correct today. So whichever arm is chosen needs the identity
at **leaf shapes only**: ident, field, index, call. That is exactly the arm set
`NodeEnumIdOf` already has, and it is a genuine reduction in both arms' cost
against what this ticket assumed.

### 2. Arm B measured, from four real channel-adding commits

| commit | what it added | compiler/ |
| --- | --- | --- |
| `6f9ecd43d` | `AliasStrElemTk` — one alias column | 3 files `+39/-1` |
| `3e01d86bd` | `LastTypePointerElemAlias` | 3 files `+69/-2` |
| `c2ad9761e` | `LastTypePointerStrCap` | 4 files `+67/-2` |
| `50ef4a29f` | the file channels (a FEATURE, not a bare channel) | 9 files `+375/-11` |

31 `LastType*` channels exist; all are reset in **one** block
(`pasparser_decl.inc:292-310`), so a new one is cheap and hard to forget. Carrier
columns per identity run 2–7 (`StrCap` 5, `EnumId` 7, `StrElemTk` 6).
`AliasEnumId` is **confirmed absent**, so the alias half of family two is
literally one column plus one read.

The reader is the expensive half, not the channel: `NodeEnumIdOf` is ~90 lines
over five node shapes, and **its own comment records a round where it named one
of five call kinds and the other four silently printed ordinals**, found by a
column census rather than by a report. That is arm B's standing failure mode,
in-tree, with a date on it.

### 3. Arm A measured — it has THREE in-tree precedents, all of this exact shape

The ticket treats arm A as unexplored. It is not. Three kinds already exist whose
**layout is an existing kind and whose semantics are not**, each added for
conversion rather than layout:

| kind | added | compiler/ | standing sites today |
| --- | --- | --- | --- |
| `tyBool8` (29) — C99 `_Bool`, storage = `tyUInt8` | `d7f68f782` 08-05 | 4 files `+77/-6` | 22 across 6 files |
| `tyUCS4Char` (30) — storage = `tyUInt32` | `b0cbeba60` 08-07 | 5 files `+144/-3` | 22 across 6 files |
| `tyWideChar` (31) — storage = `tyUInt16` | `bug-a-writeln-of-a-widechar-prints-its-ordinal` | — | — |

**Not 565 sites and not 26 `case` statements.** `tyBool8`'s own declaration says
why: *"Everything that cares about SIZE goes through TypeSlotSize/TypeIsOrdinal
and needs no change; only the conversion sites ask for this kind by name."*
That is the same predicate discipline this ticket cites as arm A's failure mode
— it is the mitigation, and it is already applied here three times.

**The coordination cost is also smaller than stated.** `TTypeKind`'s own comment
splits the enum: ordinals 0–6 *"DO NOT reorder"*, then *"appended … safe to
extend"*. Ordinals 25–31 were all appended, four of them in the last five weeks.
CLAUDE.md's rule is about **numbering**; appending to the tail is what the type
itself documents as safe. That is a message, not a negotiation.

### 4. The precedent that speaks directly to arm B

`tyWideChar` is not an analogy — it is this decision, already taken once, on a
storable type, and the reasoning is recorded at its declaration. WideChar used
**a node-level marker for eighteen months**, i.e. arm B's mechanism, and:

> *"That fallback cannot serve `WriteLn`, and this kind exists for that one
> reason."*

`WriteLn(w)` printed `65` for `'A'`. Today `WriteLn(a)` prints `1` for a
`ByteBool` — **the same consumer, the same symptom, one kind later**.
`tyUCS4Char` states the general rule beside it:

> *"A node-level marker (what WideChar uses) is not enough here: this type is
> STORABLE, and the marker is lost through a variable."*

A `ByteBool` is storable. `devdocs/dev/type-identity-as-substrate.md` names the
invariant both arms are judged against — *"decided ONCE, where the value is
introduced, and CARRIED. No later stage re-derives it from node shape"* — and a
`NodeEnumIdOf`-shaped reader is re-derivation from node shape, by construction.

### 5. A third arm exists, it looks cheap, and it is a trap

Neither option in the fork is "fix the REPRESENTATION". pxx stores `1` for a
sized boolean's `True`; fpc stores all-ones. Bitwise `not` over all-ones IS a
correct logical not, so the cheap fix is to store `$FF` and touch no types at
all. Measured:

```
pxx  a := ByteBool($FF)  ->  T.   ord=255     <- correct
pxx  a := ByteBool(1)    ->  TT   ord=1       <- broken
fpc  a := ByteBool(1)    ->  T.   ord=1       <- fpc is right either way
```

It closes four of the five broken rows **in any test written in Pascal**, and
leaves every case the type exists for still broken, because **a C library
returns `1` for true, not `$FF`** — and this ticket's own justification is
*"exactly the types an FPC binding to a C library declares"*. fpc does not rely
on the representation; it knows the type. This is CLAUDE.md's
guard-that-cannot-fail in its purest form: the fix and its natural test agree,
and neither agrees with the population. **Recorded so nobody re-discovers it as
a shortcut.**

### 6. The multiplier argument does not survive the measurement

The recommendation for B rests on *"one mechanism closes two families"*.
Measured, the families are independent and want different mechanisms:

- The enum-alias half is one missing alias column. Verified live: `type TAlias =
  TD; var a: TAlias` prints `alias=1` under pxx and `alias=dTue` under fpc, while
  a direct `TD` prints `dTue` on both. **Arm B's mechanism, ~one column, no fork
  needed** — this half is not really contested by arm A at all.
- The sized-boolean half is a storable type whose identity must survive a
  variable, which is the case `tyWideChar` already answered the other way.

So the cheapest total is not one arm. It is **B for the alias column, A for the
booleans** — and choosing that costs less than either arm applied to both.

### 7. Three claims are being bundled and they are not one class

- `if a` and `if not a` both firing (5 rows) — a compiling program taking both
  branches, no diagnostic. **Unambiguous defect under any reading.**
- `WriteLn` printing `1` — wrong output, same class as the WideChar bug.
- `Ord` answering `1` where fpc answers `-1` — this is the **signedness of the
  underlying kind** (`ByteBool` -> `tyUInt8`, so all-ones reads back `255`, not
  `-1`). It is separable, much weaker, and plausibly `known-incompat` under
  *"both answers correct about their own representation"*. Bundling it makes the
  ticket look wider than the part that is not arguable.

### Recommendation, with the measurement attached

**Split the fork.** Take arm B for the enum-alias family — it is one column and
it is uncontested. For the sized booleans the costing points at **A**, against
this ticket's recommendation, on three measured grounds: arm A has landed three
times for `+77`..`+144` and ~22 sites rather than the 565 feared; appending a
tail ordinal is sanctioned by `TTypeKind`'s own comment so the coordination cost
is a message; and `tyWideChar` is the same decision on a storable type, taken the
other way, **because the node-level marker could not serve `WriteLn`** — which is
the exact row failing here.

**The choice stays with U.** The honest counter-argument is unchanged and worth
weighing: three sized booleans plus `QWordBool` is four new ordinals for one
concept, where a carried identity is one mechanism — and `TypeIsAnyString`'s
header is in the tree precisely because enumerating kinds is how this repo has
been bitten. If A is taken, the mitigation is already named by `tyBool8`: add a
`TypeIsSizedBool` predicate in the same commit and let no consumer name the three
kinds individually.

**Not done and deliberately not done:** no code, no `TTypeKind` edit, and
`bug-p-a-sized-boolean-is-true-and-not-true-at-the-same-time` is left unclaimed —
taking it would pre-empt the fork this ticket exists to settle.
