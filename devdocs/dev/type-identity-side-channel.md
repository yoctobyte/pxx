# The type-identity side channel — the argument, the costings, the precedents

**Reference doc. Nobody needs to read this to do the work.** The decision it
supports was taken by the owner on 2026-09-06 (arm B, the side channel) and the
one-screen ticket is `decide-how-a-type-carries-an-identity-its-kind-cannot-hold`
in `backlog-core/`. This file exists because the ticket had grown to 673 lines
with a 2299-character `summary:` — four sessions' argument appended in front of
itself, which is the shape CLAUDE.md says to move into a reference doc with a
pointer.

Everything below is the ticket's body as it stood when the decision was taken.
It is history: the two costings that disagreed, the measurement that settled the
multiplier premise, the four in-tree precedents, and the obligation frankB found
on the channel. Read a section when you need the *why*; do not read the file.

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

## A fifth consumer, and it wants the distinction for the OPPOSITE reason to the fourth (frankB, 2026-09-05) — evidence, no arm picked

**A REFUSAL site, paid for with a revert.** `4760474da` tried to stop a bare
function name being stored into a procedural slot, where the ordinal result is
later called as a code address (four paths, all SIGSEGV, all silently accepted).
`TTypeKind` cannot distinguish *a pointer that will be CALLED* from *a pointer
that will be READ*, so the rule had to be written pointer-general:

```pascal
if (pType = tyPointer) and (aType <> tyPointer) then   { WRONG }
```

`TypeIsOrdinal` includes `tyChar`, so this also refused every legal
Char-into-PChar binding — `Show('-')`, `p := 'e'`, `StrLen(Char)` against
`StrLen(Pointer)`. **Thirteen rows red on seven's native tier**; reverted in
`2d6bfadd6`. The ticket is
[[bug-p-a-bare-function-name-assigned-to-a-procedural-variable-segfaults-outside-delphi-mode]].

### Why this is worth more to the fork than a fourth instance of the same thing

The other consumers are all **execution** sites: the missing distinction makes
something run wrong — an enum prints its ordinal, a bitset hands back its
element's names, a `QWord` boxes as `vtInt64`. This one is a **refusal** site,
and the failure mode inverts: a missing distinction there **rejects working
code**. Louder, safer, and found in an hour by a tier rather than sitting
silently in output nobody diffed.

**frankD's observation, and it is the sharpest thing said about this fork
today:** two consumers wanting the same distinction for OPPOSITE reasons is a
stronger argument for fixing the representation than either alone. A single
execution-site consumer can always be answered locally — special-case the
boxing, special-case the guard. A pair that needs the same fact to *emit*
correctly and to *refuse* correctly cannot both be served by a local
special-case without the two answers drifting apart, which is the condition that
makes a shared carrier worth its cost.

### And it prices arm B higher — an AVAILABILITY obligation versus a COMPLETENESS one

**Note the direction: the section above argues FOR a carrier; this sub-point
argues AGAINST the cheap arm. They are not the same claim and should not be
read as one.**

The two consumers look symmetric — same fact, two readers — and are not.
frankD's naming, which is the compression worth keeping:

- an **execution** site asks only when it is about to act, so a channel that is
  merely **AVAILABLE** when the answer is *yes* suffices. That is an
  **availability obligation**;
- a **refusal** site asks about **every assignment and every argument in the
  program**, the overwhelming majority of which have no procedural target at
  all, so the channel must be reliably correct when the answer is **no** —
  which is nearly always. That is a **completeness obligation**.

Availability can be added incrementally, one column at a time, which is exactly
what makes arm B look cheap. Completeness cannot: a channel that is right
wherever anyone remembered to fill it is *correct* under the first obligation
and *broken* under the second, and the difference does not show up until
something in the gap is exercised — `2d6bfadd6` is what that costs.

So this is a real argument against arm B rather than a restatement of the
argument for a carrier. It is a stronger obligation than
[[bug-p-a-type-alias-drops-the-enum-identity-and-a-set-drops-its-char-element-kind]]
imposed, and it is the same direction the `set of TCol` case pushed: arm B keeps
needing to answer a more precise question than "one more LastType* column".

**No arm picked. This is Track U by construction and it stays open.** Recorded
because a revert is the kind of evidence a design fork rarely gets, and because
the next person to hit the procedural case will otherwise write the same
pointer-general rule I did.


## 2026-09-06 — A FOURTH PRECEDENT, AND IT IS ARM B, ALREADY SHIPPED

Raised by the owner from memory, not from this ticket: *"i assume it's related to
retyping, like `type something = type byte` would leave something as a different
type, and not an alias of byte."*

**That construct is not in this ticket and it should be, because it is the same
decision — already taken, and taken as arm B.** `2f0ea073a` made
`T = type Base` genuinely distinct, and the mechanism is a side channel beside
the kind, not a new kind: `AliasIsDistinct` is stamped by `AliasCommit`, saved
and restored by `ParseTypeKind` around the RHS, and read at **two overload
decision points**. Measured against fpc 3.2.2: `P(b: byte)` / `P(m: TMyB)` bind
two bodies and print `base` then `distinct`, where before the fix pxx warned
*"duplicate definition of 'P' with the same parameter types"* and bound one.

**A distinct type is the purest possible case of "layout is the kind, identity is
not"** — layout-identical to the base by definition, different for overload
resolution, var-parameter matching and RTTI. If any construct were going to
force arm A, it is this one, and it did not.

So the precedent count is not three-for-A-and-one-pattern. It is:

| construct | arm taken | why |
| --- | --- | --- |
| `tyBool8`, `tyUCS4Char`, `tyWideChar` | A (own kind) | a storable type whose WIDTH differs; `tyWideChar` explicitly because a node-level marker could not serve `WriteLn` |
| enum (`SymEnumId`) | B (side channel) | layout is an integer, identity is not |
| `{$H-}` ShortString capacity (`8a3a62258`) | B | capacity has no carrier in the kind |
| **`T = type Base` (`2f0ea073a`)** | **B** | **layout IS the base by definition; only identity differs** |

**The discriminator that falls out of the table is cleaner than "which arm is
cheaper": if the WIDTH differs, it needs a kind; if only the MEANING differs, it
needs a channel.** Sized booleans are the awkward case precisely because they
differ in both — which is why they were mapped to integers for width and then
lost their booleanness. Under this rule they are a channel case that already has
its width right, not a kind case.

This does not settle the ticket; the identity-obligation requirement frankB
measured (a bare "is there an identity" channel hands a bitset its element's
member names) still applies, and applies to `AliasIsDistinct` too. But arm B is
now in the tree four times, including on the one construct that is nothing but
identity.

## 2026-09-06 (frankA) — a fifth consumer, and it is the first one that BLOCKS rather than misbehaves

frankB asked me to write this in as the fifth consumer because I built the
separate carrier first-hand. Two things to add: a witness, and a change in what
kind of argument this fork is.

### THE WITNESS: `VariantBoxToTemp`, and the remedy was a separate CARRIER, not a different field

`Variant(x)` had to be a BOXING conversion and also had to be an expression with
a TYPE. Both facts wanted the same slot — the node's `ASTTk`:

- `SizeOf` reads `ASTTk` (`szExprTk := IntToTypeKind(ASTTk[szExprNode])`), so
  leaving the operand's own kind there made `SizeOf(Variant(x))` answer 8
  against `SizeOf(vov)`'s 16 for `vov: OleVariant`.
- `IRLowerBoxOperand` takes the box's SOURCE kind **from that same field**, so
  stamping `tyVariant` on the operand node made the store copy 16 bytes out of a
  4-byte integer.

Neither value is wrong; the slot is being asked two questions. **Every
assignment to it is correct for one consumer and a pun for the other**, and no
amount of choosing better between the two available answers helps — that is the
diagnostic for this whole class, and it is the same sentence as *"a `LongBool`
carries boolean-ness AND four bytes, and the kind slot holds one"*.

The fix was neither answer: **a hidden temp of the target type**. The
assignment's RHS keeps the operand's own kind, so the box is the store `v := x`
already performs; the expression handed back is a READ of a `tyVariant` temp, so
every consumer asking "what IS this expression" gets the right answer. A second
carrier, in the AST, at the point of use (`b531be20a`, `5d29f9cd7`).

**What it costs to read as a precedent, honestly:** an expression node is not a
type. A temp is available to me because a cast has a point of use; a `LongBool`
FIELD in a record has no such point, and a declaration boundary is exactly where
today's identity dies. So this is evidence for the SHAPE of arm B — a second
carrier beside the layout kind — and it is **not** evidence that the carrier can
be cheap, because mine was cheap for a reason that does not generalise.

I also record the one thing I got wrong there, since it bears on B's obligation:
I first wrote the lost static type off as CLAUDE.md's implementation latitude,
and it was not — the failing row asserts that OUR `OleVariant` and OUR
`Variant(x)` agree with EACH OTHER, and no parity clause reaches a relation
between two of our own answers. **A carrier that is merely "usually right" will
be defended with a latitude argument the first time it is caught**, which is a
reason to state B's identity obligation as a rule rather than as a convention.

### THE CHANGE IN THE ARGUMENT: `BooleanNN` cannot be written correctly today

frankB measured, before writing a line, what a `Boolean16` row would have to
contain — and `defs.inc` has exactly two boolean kinds, `tyBoolean` and
`tyBool8`, **both one byte**. So the row has two available spellings and both
are defects:

| spelling | width | `Ord(True)` | `not` | `WriteLn` |
| --- | --- | --- | --- | --- |
| `tyUInt16` | 2 ✓ | 1 ✓ | arithmetic complement ✗ | prints a number ✗ |
| `tyBoolean` | **1 ✗** | 1 ✓ | ✓ | ✓ |

The second is the failure the mapping's own comment exists to forbid. The first
is the p55 bug, reproduced in four fresh names.

**That converts this fork from an argument into a schedule.** The other four
consumers are wrong behaviours in code that already exists — real, ranked, and
survivable. `feature-p-the-booleannn-family-of-explicit-width-boolean-type-names`
is code that **cannot be written correctly until this fork moves**, and
`uthlp.pp` plus twelve `tthlp*` corpus files are behind it. A fork with four
defects behind it can be deferred; a fork that blocks a feature outright has a
date.

And frankB's ordering hazard is the sharpest thing on either ticket, so it
belongs here too: **a missing name produces an error message and a wrong branch
does not.** Land the four names alone and the corpus wall moves, the pass count
improves, and the improvement comes from the half that mattered least while
`not` stays inverted on the whole family.

### RECOMMENDATION

Unchanged: **B**, with the identity obligation frankB derived from the
`set of TCol` case stated as a rule — a channel must answer *whose* identity it
carries, not merely *that* there is one. My contribution to the recommendation
is only the negative: do not price B from the Variant precedent. That carrier
was cheap because a cast has a point of use, and the declaration boundary — the
place this fork actually has to survive — is the one place my fix never had to
work.

### A THIRD FACE OF THE BOOLEAN FAMILY, from an unrelated instrument

My door-selector sweep on
`refactor-p-five-dispatch-sites-for-one-named-type-cast` carried LongBool and
ByteBool rows as filler and both came back differing from fpc:

    WriteLn(LongBool(LongInt(2)))   ->  pxx 2   fpc TRUE
    WriteLn(ByteBool(LongInt(258))) ->  pxx 2   fpc TRUE

No `not`, no `{$if sizeof}`, no corpus. So the family is wrong in three
positions — `not`, `WriteLn`, and the Ord/ABI face — reached by three unrelated
routes. Recorded because **three faces from one cause is the shape that stops
the next reader filing a fourth.**

## THE FIELD BOUNDARY — a further consumer, and it recurses rather than adding a second lossy hop (frankB, 2026-09-06) — evidence, no arm picked

> **Numbering note.** This ticket now carries two sections labelled *fifth
> consumer* — mine of 2026-09-05 and frankA's of 2026-09-06, written
> independently. **The ordinals have stopped being a count**, so I have dropped
> the number from this one rather than add a third ambiguous ordinal. Consumers
> are distinguished by their SUBJECT, not their position: this one is the record
> FIELD.

frankA made the field case as a structural CLAIM: *"a cast has a point of use; a
`LongBool` FIELD has no point of use, and the declaration boundary is exactly
where today's identity dies — the one place my fix never had to work."* The
claim is right and a reader could have disbelieved it for free, so here it is as
rows. `type TR = record flag: LongBool; n: Integer; end`, measured 2026-09-06
against fpc 3.2.2, pxx binary `827722c842de` (the tree at `d3fe44947`):

| row | pxx | fpc |
| --- | --- | --- |
| `SizeOf(r.flag)` | 4 | 4 |
| `SizeOf(TR)` | 8 | 8 |
| `if not r.flag` after `r.flag := True` | **TAKEN** | skipped |
| `WriteLn(r.flag)` | **1** | `TRUE` |

**The top two rows are the finding, not the filler.** The width crosses the
declaration boundary INTACT — through `UFldTk`/`RecFieldType` — and the record
layout is right in both compilers. So the field carrier is not lossy, and
"the identity dies at the declaration boundary" is not quite the mechanism:
**the slot keeps the same fact one level down that it kept upstairs.** This is
one-slot-two-facts RECURSING, not a second lossy hop.

Two estimates change, both downward:

- **Nothing in the field machinery needs fixing.** Arm B's carrier has to
  TRAVEL WITH the field; it does not have to replace how fields carry types.
- The structural shortfall is still real — a field has no point of use, so no
  cast-shaped fix reaches it — but it costs a channel that recurses, not a
  rewrite of `UFldTk`.

### The cheapest demonstration in the ticket, and it is a HALF fix (frankA's, recorded here)

frankA fixed the enum-alias identity this morning (`type TE = TMyEnum; TE(1)`
printed `1` where `TMyEnum(1)` printed `eB`), then found the fix was half a fix.
The guard was

```pascal
if IntToTypeKind(AliasTk[aliasIdx]) = tyInteger then { take the enum id }
```

which is a correct test only while every enum IS `tyInteger`. Under
`{$PACKENUM 1}` an enum's storage kind is `tyUInt8`, the guard goes false, and
the identity drops again: `TS2(1)` printed `1` where `TSmall(1)` printed `sB`.
The sibling door's own comment predicted this in almost those words and had been
read hours earlier — **the kind is the only handle in reach, and it is right
often enough to look like the question.** The fix reads the alias table's
identity COLUMN, which answers "is this an enum" without asking anything about
the kind: arm B, one line, one site.

**A guard written on the layout kind is a bet that the layout kind will never
narrow** — and narrowing it is exactly what `{$PACKENUM 1}`, `tyBool8`,
`tyWideChar` and `{$H-}` `ShortString` all do. Every instance in this fork's
history is that same bet losing.

Method note attached to it, because it is the reason the half-fix shipped: the
row set that missed it varied the DOOR and held the directive at its default.
**A probe is naturally written at the default value of every setting it is not
about**, and `{$PACKENUM}` is file-scoped — so the second value needed a second
FILE, and folding the two together would have silently dropped the default half.

### The membership test for this fork, which is cheaper than arguing about it

**If a bug can be fixed by reading a different field, it is NOT this fork.**

Group 19's `FileIOArgSize` was exactly that: the kind came from the node and the
capacity from the symbol, and the fix was to read the kind out of the same
record. The fact existed; one caller looked in the wrong place. Here there is no
other field to read — once the kind slot holds `tyInteger`, **no slot anywhere
holds "this is a boolean"**, and that is what makes it a carrier question rather
than a lookup bug. Apply it to an incoming ticket before attaching it to this
fork; it separates the two classes in one question.
