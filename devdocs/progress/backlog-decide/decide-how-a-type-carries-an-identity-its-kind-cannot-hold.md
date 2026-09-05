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
summary: "Two open bug families have ONE cause: a type whose LAYOUT is an existing kind but whose SEMANTICS are not. ByteBool/WordBool/LongBool are tyUInt8/tyUInt16/tyInteger so their C-ABI width is right, and nothing downstream can tell them from integers -- so `if a` and `if not a` BOTH fire (p55), WriteLn prints 1 for TRUE, and Ord answers 1 where fpc answers -1. Separately an alias to an enum, and a set's char element, drop their identity the same way (p40). The fork: (A) give the sized booleans distinct TTypeKinds, which touches defs.inc's kind numbering -- the ONE thing CLAUDE.md says to coordinate by message rather than edit; or (B) generalise the pattern an enum already uses (tyInteger PLUS an id) into a side channel carried through symbols, fields, params and the alias table, which closes BOTH families in one move. Recommendation: B. A costing of the Pascal-frontend arm is appended (frankB, 2026-09-05, compiler 47618f77c240) and DISPUTES the multiplier premise: the two families are independent, arm A has three in-tree precedents (tyBool8/tyUCS4Char/tyWideChar) that landed for +77..+144 and ~22 sites rather than the 565 feared, and tyWideChar is this same decision on a storable type taken the OTHER way because a node-level marker could not serve WriteLn. Then MEASURED against arm A: frankB narrowing an enum off tyInteger (324641046) detached the enum identity at seven sites guarded by `kind = tyInteger` and NOTHING failed, and frankB's `set of TCol` case shows a bare "is there an identity" channel would hand a bitset its element's member names, so B's channel must answer WHOSE identity it is. frankB then corrected the cost: the set case is NOT a freshness bug -- the channel is valid, current and about the wrong subject -- so arm B needs an IDENTITY obligation on every channel, not the window discipline the existing LastType* channels already have, and "one more of the same" underprices it. A third construct of the same shape has since landed (8a3a62258, {$H-}: BareStringKind returned tyShortString at every site while SizeOf answered 8, because a ShortString's CAPACITY has no carrier in the kind) -- fixed, so a precedent rather than a fourth family, and it makes this a PATTERN in the type system rather than two coincidences. Choice still open with U."
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

---

## 2026-09-05, later — arm A's failure mode is no longer predicted, it is MEASURED

frankB's `{$PACKENUM}` work (`324641046`, `167847e61`) narrows an enum's storage
kind off `tyInteger`, which is arm A's move applied to enums. Its own report:

> *"narrowing the enum's kind off tyInteger silently detached the enum's
> IDENTITY at seven sites that guarded the stamp with `kind = tyInteger`.
> WriteLn of a packed enum printed an ordinal instead of a member name —
> through a variable, a record field and a cast — and nothing failed."*

**Seven sites, no failure.** That is the enumerate-the-kinds hazard this ticket
cited from `TypeIsAnyString`'s header, now observed rather than argued, on the
first type that took arm A's shape. It strengthens the recommendation for B.

### …and it sharpens what B must actually do

The same report carries a constraint that the recommendation above was too loose
about:

> *"The kind half is NOT redundant with `enumId >= 0` and cannot just be
> deleted: `set of TCol` leaves LastTypeEnumId holding the ELEMENT's id, so the
> kind test is what stops a bitset inheriting a member name."*

So "identity beside the kind" is not sufficient on its own. A channel that only
answers *"is there an identity"* will hand a `set of TCol` its element's member
names. **The channel has to answer whose identity it is** — bound to the thing
being declared, not left as the most recent id any nested parse deposited. That
is the window discipline every existing `LastType*` channel documents, and it is
sharper here because for a set the "stale" value is not from an unrelated
declaration but from a legitimate nested one.

frankB's fix routes all seven through one predicate comparing against
`EnumStorageTypeKind` rather than a list of kinds, which is the right local
shape and is also the shape B would generalise: **one predicate, not N call
sites each restating the rule.**

### What has not changed

Both bugs this fork would close still reproduce at `167847e61`, measured rather
than assumed: an alias to an enum still prints `1` where fpc prints `tue`, and
`Low`/`High` of `set of 'c'..'k'` still answer `99 107` where fpc answers `c k`.
Neither was touched by the packenum work, which is expected — those losses are
at the alias/set registration boundary, not at the kind-guard sites.

---

## 2026-09-05, later still — the set case is not a FRESHNESS bug, and a third instance landed

Two corrections/additions from frankB, both about this fork rather than about a
ticket. Recorded here because they change what arm B costs, and the cost was the
part this record was thinnest on.

### The `set of TCol` hazard is not the hazard the existing channels guard

The section above filed this under "window discipline". frankB's correction, and
it is right:

> *"The stale value there is not stale in the usual sense. Every existing
> `LastType*` comment warns about a reader outside the window picking up what an
> UNRELATED declaration left behind. This is not that. `set of TCol` fills
> LastTypeEnumId correctly, for a real nested type, in the very declaration being
> parsed — so the channel is valid, current, and about the wrong subject. No
> window rule catches it, because nothing is out of window."*

That is why the landed guard asks `tk = EnumStorageTypeKind(etid)` and not
`etid >= 0`: **it is an identity test, not a freshness test.** Freshness
discipline alone would not have saved it, and a reviewer who checked only that
the channel was written inside the window would have passed the broken form.

**So the honest cost note for arm B: the discipline it needs is NOT the
discipline the existing channels already have.** "One more `LastType*` channel,
same rules" understates the work by exactly this case. Whoever settles this fork
should price B with an identity obligation on every channel, not a freshness one.

### A third construct where the kind was right and the type was still wrong

`{$H-}` / `{$LONGSTRINGS OFF}` landed at `8a3a62258` (verified on origin;
touches `defs.inc`, `lexer.inc`, `paslexer.inc`, `pasparser_decl.inc`,
`pasparser_expr.inc`, `util.inc`). frankB's report of the mechanism is the same
shape as the enum-identity one and worth this ticket's attention:

> *"I instrumented BareStringKind and watched it return tyShortString on every
> call while SizeOf answered 8 — a ShortString's CAPACITY has no carrier in the
> kind, so `string[N]` sets LastTypeStrCap from N, the `shortstring` NAME sets
> 255, and a bare `string` under {$H-} is the third spelling of that same type
> and had to set it too. Then SizeOf needed the identical missing fact a second
> time, because TypeSlotSize takes a kind with no capacity."*

**The kind was correct at every declaration site and the type was still wrong.**
Two sites, one omission, because the kind and the capacity are one fact and
neither half is sufficient alone.

This is a PRECEDENT, not a fourth open family — it is fixed. It belongs here
because it is a third independent construct whose semantics do not fit its
`TTypeKind` (after the sized booleans and the enum/set identity), and because it
was resolved the way arm B resolves things: a fact carried beside the kind,
required at every spelling that can produce the type. **A third instance makes
this a pattern in the type system rather than two coincidences**, which is an
argument for settling the fork generally rather than per-family.

Deliberately NOT filed from frankB's report, and noted so a later reader does not
mistake the silence: `{$mode objfpc}` does not imply `{$H+}` in fpc (only
`{$mode delphi}` does), so pxx's default bare string matches fpc in delphi mode
only. frankB measured it, it is pre-existing, and it is the managed-string model
this compiler chose — a chosen divergence, not this fork's business.

---

## A fourth consumer, from the library side (frankH, 2026-09-05) — evidence, no arm picked

Found while measuring what a library `writeln` must reproduce for phase 3 of
[[feature-writeln-as-library]], by a session that had not read this fork. Adding
it because it is the same missing identity reaching a consumer none of the three
recorded ones covers, and because **it constrains both arms rather than
favouring either.**

### The measurement

`array of const` boxing, at compiler `9bcfd2b4da30`, one program printing
`a[i].VType`:

| declared | tag emitted |
| --- | --- |
| `Boolean` | 1 `vtBoolean` |
| `WordBool` | **0 `vtInteger`** |
| `LongBool` | **0 `vtInteger`** |

So `sysutils.Format`, any user variadic, and the phase-3 library `writeln` all
receive a sized boolean *described as an integer* and render `1`. The builtin
`writeln` prints `TRUE`. Same split as the three consumers already listed —
`WriteLn(a)`, `not a`, `Ord(a)` — reached independently.

### Why this one is not just a fourth instance of the same thing

Section 4 records `tyWideChar`'s declaration saying a node-level marker *"cannot
serve `WriteLn`"*, and `tyUCS4Char` sharpening it to *"the marker is lost through
a variable."*

**At an `array of const` boundary the marker is not merely lost — there is no
node to lose it from.** The value is written into a runtime `TVarRec` whose
`VType` tag is the *entire* description that survives, and the consumer is
ordinary Pascal in another unit, reading that tag at run time with nothing else
to consult. Not a later compiler stage that could in principle re-derive from
node shape: a `case v.VType of` in `lib/rtl/sysutils.pas`.

That makes this the strictest test either arm has to pass, and it is a
**requirement, not an argument for a winner**:

> whatever carries the identity must be readable at the `AN_VARREC_ARRAY`
> boxing site in `ir.inc`, because that is where the last chance to write it
> into the tag is.

Arm A meets that by construction — a distinct kind is visible at the box site
like any other. Arm B is not thereby excluded; its channel simply has to be
one lowering can read there, and that is a question about the channel's design
rather than about the arm. **Whoever settles this should check the chosen arm
against that site specifically**, because the boxing site is the one consumer
where "re-derive it later" is not merely discouraged but impossible.

The tag space is not the obstacle: `vtBoolean` already exists and is already
emitted correctly for a plain `Boolean`. The boxing arm simply has no way to
ask "is this an integer, or a boolean stored in an integer" — which is this
ticket's sentence, at a fourth site.

### Explicitly not part of this fork

The same measurement found `QWord` boxing as `vtInt64` where fpc emits
`vtQWord` ([[bug-a-a-qword-boxes-as-vtint64-so-array-of-const-loses-unsignedness]]).
**That is a different animal and does not belong here.** `vtQWord` exists, is
declared, and simply is not emitted — the identity has a carrier and nothing
writes to it, where this fork is about an identity with no carrier at all.
Recorded so the next reader does not bundle them: they were found in one
program, and that is their only relationship.

No arm picked, and deliberately: two sessions have costed this fork already and
it is the owner's to settle.

