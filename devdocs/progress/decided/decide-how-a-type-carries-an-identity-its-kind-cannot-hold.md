---
slug: decide-how-a-type-carries-an-identity-its-kind-cannot-hold
title: "Carry a type's identity in a side channel beside its kind — DECIDED, arm B"
track: A
type: feature
prio: 55
status: decided
owner: ""
created: 2026-09-05
decided: 2026-09-06
blocked-by: []
summary: "DECIDED AND BUILT 2026-09-06 (frankH): arm B, four slices -- ef518700b vehicle, 71b5bac58 renderers+operators, e06cfdeeb True-materialisation, 1e4852261 fields/params/return types/alias table. All carry sites done. Both consumer bugs closed. Encoding: one Integer, enum family numerically UNCHANGED (>= 0), every other family NEGATIVE so an unwidened `>= 0` reader correctly sees `not an enum` -- that is what let the sites widen one at a time. The `whose identity` obligation was already met by NodeSemIdOf and EnumKindMatches and needed widening, not inventing. Original fork: DECIDED BY THE OWNER 2026-09-06: arm B, the side channel, even though it is the bigger overhaul. Some types have the LAYOUT of an existing TTypeKind and different SEMANTICS, and today only the kind survives a declaration, so the semantics are lost at the first registration boundary. Generalise the pattern an enum already uses (tyInteger PLUS SymEnumId) into an identity carried through symbols, record fields, params, return types and the alias table. THE RULE THAT FELL OUT AND IS WORTH MORE THAN THE CHOICE: if the WIDTH differs it needs a kind; if only the MEANING differs it needs a channel. Four in-tree precedents for B, including `T = type Base` (2f0ea073a), which is nothing BUT identity. ONE OBLIGATION, measured: a channel must answer WHOSE identity it is -- a bare `is there an identity` hands a `set of TCol` its element's member names. Unblocks bug-p-a-sized-boolean-is-true-and-not-true-at-the-same-time (p70) and bug-a-the-sized-booleans-render-as-a-digit-in-both-str-and-writeln. Argument, costings and precedents: devdocs/dev/type-identity-side-channel.md.
---

# Decided: the identity goes in a side channel, not in a new kind

Owner, 2026-09-06:

> *"as i read it, the ticket already came to the conclusion — option B is the
> right one, even if that's the biggest overhaul."*

## The rule, which outlives this ticket

**If the WIDTH differs, it needs a kind. If only the MEANING differs, it needs a
channel.** That discriminator is why the tree already looks the way it does:
`tyBool8`, `tyUCS4Char` and `tyWideChar` are their own kinds because they are
stored differently; enums, `{$H-}` ShortString capacity and `T = type Base` are
side channels because they are not.

**The sized booleans are the awkward case because they differ in both** — which
is exactly how they got here. Mapping `ByteBool`/`WordBool`/`LongBool` onto
`tyUInt8`/`tyUInt16`/`tyInteger` got the C-ABI width right, deliberately and
correctly, and lost the booleanness. Under this rule they are a channel case
whose width is already correct.

## What to build

Generalise `SymEnumId` into a semantic identity carried through **symbols,
record fields, params, return types and the alias table**. `RegisterGeneralAlias`
already reads `LastType*` channels for a pointer's pointee, a string capacity, a
file element width, a managed-string element width and a subrange's bounds — the
carry sites are enumerated and have precedent.

**THE ONE OBLIGATION, and it is not "one more of the same":** every channel must
answer **whose** identity it is. Measured by frankB — a bare "is there an
identity" channel hands a `set of TCol` its *element's* member names. The
existing `LastType*` channels need window discipline; this one needs a subject.

## What it unblocks

| ticket | prio | what it is |
| --- | --- | --- |
| `bug-p-a-sized-boolean-is-true-and-not-true-at-the-same-time` | 70 | `if a` and `if not a` BOTH fire; `not` on a sized boolean is an integer complement |
| `bug-a-the-sized-booleans-render-as-a-digit-in-both-str-and-writeln` | 35 | `WriteLn`/`Str` print `1`, FPC prints `TRUE`; `Ord` answers 1 against FPC's -1 |

plus the enum-alias half: `type TDays = D` prints `1` where FPC prints `tue`,
because the alias table has no column for the id.

**Already fixed and NOT part of this work:** `T = type Base` (`2f0ea073a`) —
`AliasIsDistinct`, stamped at alias commit, read at two overload decision
points. It is arm B on the purest case and it is the precedent, not the task.

## Where the argument went

`devdocs/dev/type-identity-side-channel.md` — the two costings that disagreed,
the measurement that killed the multiplier premise, the four precedents, and the
`set of TCol` case that produced the obligation above. **Do not read it to do the
work; look a thing up in it.**

## 2026-09-06 — RELAYED: THE OWNER HAS DIRECTED AN IMPLEMENTATION, AND THIS TICKET STILL READS `status: open` / `owner: ""`

**Recorded by frank-coordinator as a RELAY, not as a decision.** Source: frankuser,
who states that the owner has directed **frankH** to implement the type-identity
side channel, **started 2026-09-06, ahead of the ranker**, with its session context
cleared for a self-contained brief. **arm B** — frankuser's note that *"arm B adds
no `TTypeKind`"* is the identifying detail.

**I have not moved this ticket and will not.** The folder move to `decided/` and
the `status:`/`owner:` fields belong to frankuser or frankH; a coordinator
recording a relayed instruction is not the same act as closing a decision, and the
distinction is the whole reason this note is phrased as provenance. **If the relay
is wrong, this paragraph is wrong and the frontmatter is still right.**

**Why it is written here at all:** a decision ticket that reads `open` with
`owner: ""` while it is being implemented is an invitation to re-litigate the fork
or file a competing recommendation, and the reader who does that has done nothing
wrong — the board told them it was undecided. This ticket sits at effective p70
with `(unblocks 3)`, so it is visible from `ready --track U` and from every
consumer's blocker list.

**The three edged consumers, so whoever closes this knows what falls out:**

- `bug-p-a-sized-boolean-is-true-and-not-true-at-the-same-time`
- `bug-a-the-sized-booleans-render-as-a-digit-in-both-str-and-writeln`
- `feature-p-the-booleannn-family-of-explicit-width-boolean-type-names` — the edge
  added today on frankA's measurement, and the only one of the three that is code
  that **cannot be written correctly** rather than code that behaves wrongly

**And one live coordination fact for whoever picks this up**, because it is not
derivable from the board: `refactor-p-five-dispatch-sites-for-one-named-type-cast`
(`working/`, `owner: frankA`) has as its remaining work *"one `name -> (castKind,
enumId, aliasIdx)` resolver replacing `FindTypeAlias` and `BuiltinScalarTypeKind`
being asked separately"* — **the alias table's READ door, while this implements its
registration door and side channels.** Flagged to both seats. The ticket also
carries the load-bearing constraint an implementer would not otherwise have:
`FindTypeAlias` must be consulted **before** the builtin lookup, because a source
declaration outranks a builtin and `symtab.inc` documents that inverting it
silently breaks the compiler — and the natural spelling is builtin-first, which is
how it came to be wrong once already (`4be17cb8f`).

### AND THE EDGES ARE NOT ALL THE SAME STRENGTH — frankA, `9341b19ac`, measured after the annotation above

**The fork is no longer the only route to a defensible state for part of this
family**, and nobody could see that because nobody had asked the second spelling.

`High(ByteBool)` is **REFUSED** at the direct door — deliberately, because
`ByteBool`/`WordBool`/`LongBool` map to `tyUInt8`/`tyUInt16`/`tyInteger` to keep
their C-ABI width, so answering `High` from the kind would give an ordinal. **The
alias spelling has no such scruple:** `type b = ByteBool; High(b)` answers **255**
(WordBool 65535, LongBool 2147483647). fpc answers `TRUE` for both spellings.

**So there are two repairs and only one of them is behind this fork:**

| repair | needs the fork? |
| --- | --- |
| make them answer **`TRUE`** | **yes** — the kind must carry width and boolean bounds together |
| make the two spellings **AGREE** | **no** — the alias path can refuse exactly as the direct path does, today, and that is strictly smaller than the fork |

**A refusal is loud; a wrong bound is silent, and the ACCEPTED spelling is the
worse of the two.** The direct door is declining a question it cannot answer
correctly and the sibling answers it wrongly.

**Consequence for whoever closes this fork:** a `blocked-by` edge records that
*some* repair needs the blocker, and reads as though *every* repair does. The three
consumers on this one are not equivalent — `feature-p-the-booleannn-family-...` is
code that cannot be written correctly at any spelling available today, while part
of the sized-boolean family has a smaller, unblocked route to a defensible state.
**Say which repair an edge is about when the ticket admits more than one.**

## Log
- 2026-09-06 — decided; this names the commit that carried the decision, which is not always the one that carried the change — commit PENDING-COMMIT.

## 2026-09-06 — BUILT (frankH). Arm B, four slices, all carry sites

`ef518700b` the vehicle · `71b5bac58` renderers and boolean operators ·
`e06cfdeeb` `True` materialisation · `1e4852261` fields, params, return types,
alias table.

### The encoding, and why the non-enum families are NEGATIVE

A SemId is one Integer. **The enum family is numerically exactly what
`SymEnumId` always held** (`>= 0`, the enum type index); `SEM_NONE` is -1; every
other family lives below `SEM_BOOL_BASE` (-16).

That is not packing, it is the migration strategy. Every pre-existing reader of
an enum channel asks `>= 0` or `< 0`, so an identity from a new family arriving
in a channel whose readers have not been widened is **invisible to them and
reads as "not an enum" — which is true.** A positive encoding would have made a
sized boolean read as *enum type 0* in every unmigrated reader, which is the
exact failure `AliasEnumId`'s own comment records. This is what let the carry
sites widen one at a time across four commits, each landing green.

**The channels renamed track exactly what was widened.** `LastTypeSemId`,
`SymSemId`, `ASTSemId`, `UFldSemId`, `ProcRetSemId`, `ProcParamSemId`,
`AliasSemId`, `ptypesSem`. The set/array-index enum channels keep their names —
a channel that still holds nothing but enum ids is truly named, and renaming it
would have been the lie this repo's own rule warns about.

### THE OBLIGATION was already met, in one place, and it needed widening not inventing

`NodeSemIdOf` (was `NodeEnumIdOf`, `pasparser_expr.inc`) already answered
**whose** identity per node shape — ident vs ARRAY ident vs index vs field vs
call — and already refused to let a whole array claim its element's. Widening
its **payload** rather than its **structure** discharged the obligation for
free. `SemKindMatches` is `EnumKindMatches` generalised: the window guard that
stops `set of TCol` inheriting its element's identity, one function per family
rather than a copy per carry site. **Both were pre-existing and both were the
right shape.** Nothing new had to be invented to answer "whose".

### The bug that made the last two sites look unfixable

`NodeSemIdOf`'s fallbacks read `if Result < 0 then Result := ASTSemId[node]`.
Exact while enums were the only family. A sized boolean's identity is negative,
so the field, index and call arms each **found the right answer and threw it
away three lines later** — the channels were stamped correctly and the values
still printed as ordinals. Same shape one level down in four guards asking
`tk = tyInteger` to mean "does this type have an identity", already broken by
`{$PACKENUM}` before the booleans arrived.

### The thesis, demonstrated rather than argued

`a xor b` on two sized booleans is left **bitwise**, matching fpc 3.2.2, and its
result keeps the sized-boolean identity. So `WriteLn(a xor b)` prints `TRUE`
while `Ord` of that same expression is `-55`:

> **One value, a boolean TYPE and an integer PATTERN — which is exactly the pair
> a kind alone cannot hold.**

That is this ticket's thesis with a program attached, and it is why the
asymmetry (`and`/`or` logical, `xor` bitwise) is deliberate and must not be
"fixed" by a later reader.

### What it cost to get wrong, recorded because it is the general lesson

The first `not` fix set `bitNot := False` and let the logical path take the
operand as-is. **The logical path lowers to `xor 1`** — correct for a canonical
0/1 Boolean, wrong for `ByteBool(200)`, since `$C8 xor 1` is `$C9` and still
true. It was caught only because the test carried a nonzero-but-not-one row.

The same blind spot had hidden a whole family from every existing ticket:
`and`, `or` and the six comparisons were all wrong on a sized boolean and
nobody had them, **because every probe used 0 and 1** — inputs on which the
broken path and the correct path agree. `a and b` for two true values answered
`0`; `a = b` answered `FALSE`.

> **A probe you are going to reason FROM needs a correct answer the failure mode
> cannot produce.** Wherever a type's default, a zero, a `sizeof(int)`, a
> canonical `1` or a pointer width is also the expected value, the guard cannot
> fail.

### Two things found by peers, both load-bearing under this change

- **`CloneAST` was not copying the identity slot** (frankA, flagged honestly as
  a lead with no repro). While it held an enum id a clone cost a *diagnostic*;
  carrying "integer kind, boolean semantics" it would have cost the p70
  control-flow bug **in cloned subtrees only** — inside a for-in, a `SetLength`
  desugar, an inline expansion — intermittent by construct shape and looking
  like nothing to do with this work. Its header claimed the copy list was
  complete, which is what kept it invisible; grepping `AllocNode` for the rest
  of that claim found the sibling, `ASTCLongRank`, missing too.
- **The signedness and the `True` materialisation are different questions**
  (frankA, measured). `tyInt8`/`tyInt16` fixes `Ord(ByteBool(255))`; only
  materialising all-bits-set fixes `Ord(b)` after `b := True`. **LongBool has
  been signed the whole time and still answered 1**, which is the control that
  separates them. A row set built on `True` reads as "the change did nothing";
  one built on `255` reads as "sized booleans are fixed". Both wrong, both one
  plausible test file away — the tests now carry both, labelled.

### Not done, deliberately

`SymElemEnumId` and the set/array-index channels are still enum-only, so an
`array of ByteBool` element and a `set of` element carry no boolean identity.
They are handed `SemEnumOf(...)` at the stamp sites, which reads as `SEM_NONE`
there — the truth, since nothing can use it yet. Drop that conversion when
those channels are widened, not before.
