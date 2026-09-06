---
slug: decide-how-a-type-carries-an-identity-its-kind-cannot-hold
title: "Carry a type's identity in a side channel beside its kind — DECIDED, arm B"
track: A
type: feature
prio: 55
status: open
owner: ""
created: 2026-09-05
decided: 2026-09-06
blocked-by: []
summary: "DECIDED BY THE OWNER 2026-09-06: arm B, the side channel, even though it is the bigger overhaul. Some types have the LAYOUT of an existing TTypeKind and different SEMANTICS, and today only the kind survives a declaration, so the semantics are lost at the first registration boundary. Generalise the pattern an enum already uses (tyInteger PLUS SymEnumId) into an identity carried through symbols, record fields, params, return types and the alias table. THE RULE THAT FELL OUT AND IS WORTH MORE THAN THE CHOICE: if the WIDTH differs it needs a kind; if only the MEANING differs it needs a channel. Four in-tree precedents for B, including `T = type Base` (2f0ea073a), which is nothing BUT identity. ONE OBLIGATION, measured: a channel must answer WHOSE identity it is -- a bare `is there an identity` hands a `set of TCol` its element's member names. Unblocks bug-p-a-sized-boolean-is-true-and-not-true-at-the-same-time (p70) and bug-a-the-sized-booleans-render-as-a-digit-in-both-str-and-writeln. Argument, costings and precedents: devdocs/dev/type-identity-side-channel.md."
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
declaration outranks a builtin and `symtab.inc:6215` documents that inverting it
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
