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
