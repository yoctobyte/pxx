---
slug: bug-a-a-set-is-32-bytes-whatever-its-bounds-and-the-ir-opcode-says-so
title: "A set is 32 bytes whatever its bounds — and the size is written into the type kind and an IR opcode's contract"
track: A
prio: 30
type: bug
status: rainy-day
created: 2026-09-02
found-by: frankuser
owner: ""
summary: "PARKED BY THE OWNER 2026-09-02 — sets are 32 bytes, always, and that is CHOSEN, not tolerated. Deferred rather than rejected: it is solvable at an overhead, and solving it could beat FPC by rebasing to `lo` (FPC does not, so `set of 'x'..'z'` costs it 32 bytes for three bits). WHAT PARKING COSTS, measured and accepted: a record containing a small set cannot blit to a typed file — 32 bytes in memory, 4 on disk, every later field shifted — so `file of T` marshals field-by-field there, and the docs must advise against records-with-sets for file IO. WHAT IT DOES NOT COST: bare-set file IO, which needs no change at all, because our 32-byte mask is a byte-exact ZERO-EXTENSION of FPC's set (measured both size classes) — write 4 bytes when the declared high bound is <= 31, else 32. ORIGINALLY SPLIT OUT of compat-pascal-four-type-sizes-... at frankb-a9's request, because it shares neither cause nor lane nor size with the string[N] third it was bundled with. `set of 0..7` is 32 bytes in pxx; FPC gives 4 — a small-set word whenever the HIGH bound is <= 31, and 32 above it (FPC does not rebase to `lo`, so `set of 200..207` is 32 in both). A 32x footprint on the commonest small set, and not a wrong VALUE: every set operation is correct, which is why no differential probe reaches it. NOT a parser change and not a mapping change: 115 `tySet` sites, 39 `IR_SET_COPY`/`IR_SET_LIT` sites, and the width is baked into two contracts rather than a table — `defs.inc:2003` defines the kind itself as `{ 21: Set — 32-byte bitset }` and `defs.inc:1097` documents `IR_SET_COPY` as `copy full 32-byte set`. So it is a codegen/ABI slice: a variable-width set changes the by-value ABI class and every backend's copy, and both IR opcodes' contracts have to change with it."
---

# A set is 32 bytes whatever its bounds

> **PARKED 2026-09-02 BY THE OWNER.** *"let's park it for now. i'd say, for now,
> our sets are just always 32 byte. and advise against using records with sets
> for file-io or document it."*
>
> **rainy-day, not rejected and not low-prio** — the measurement is true, the
> improvement is real, and it is a future plan rather than a non-goal. Narrowing
> would buy three things at once (FPC-identical `SizeOf`, blittable records for
> `file of T`, and ESP memory) for one ABI change; the owner judged the overhead
> not worth it now, having seen all three. The decision and every measurement
> behind it are in
> [[decide-a-what-a-set-costs-bits-bytes-bounds-and-what-file-of-t-writes-to-disk]].
>
> **THE MECHANISM IS ALREADY DESIGNED, and it is cheaper than the estimate this
> was parked on.** The owner's `smallset` proposal — a hidden second type kind,
> same `set` keyword in source — avoids variable-width sets entirely, because a
> small set is a DWORD riding existing scalar machinery. Measured: of 115
> `tySet` sites, 54 are bare kind tests (mechanical) and only 9 are size or copy
> decisions. Design it with ONE `IsSetKind()` predicate, never 54 two-armed
> comparisons. Full write-up in the decide.
>
> **Reopen it with**: a real program that the 32-byte width makes infeasible —
> an ESP target that runs out of RAM on set-heavy code, or a record-file format
> that must blit. Not a `SizeOf` probe: under the 2026-09-02 rule
> `SizeOf(set of 0..7)` = 32 is a true statement about our representation.

## Why this is its own ticket

It arrived as third (2) of `compat-pascal-four-type-sizes-…`, beside the
`string[N]` third. **frankb-a9 asked for the split after fixing the string
half** and the reason is ranking, not tidiness: bundled, the set half inherits a
priority the string half earned and reads as comparably tractable to whoever
picks it up. It is not. The string half was a matter of asking the right sizing
function; this one changes an ABI class.

## Measured

`set of 0..7` — pxx **32**, FPC **4**. FPC's rule is the small-set word: 4 bytes
when the high bound is ≤ 31, 32 above it, **and it does not rebase to `lo`** —
so `set of 200..207` is 32 in both compilers and only the low-bounded case
diverges. That is the common case; `set of Char` and `set of 0..255` are
already agreed.

**FPC's rule measured first-hand 2026-09-02 (3.2.2, `-O-`): the width is a
function of the HIGH BOUND ALONE** — 4 if `hi <= 31`, else 32. No rebasing, no
span term: `set of 32..63` spans exactly 32 values and still costs 32 bytes,
and `set of 'x'..'z'` costs 32 for three bits. This confirms frankb-a9's
no-rebase measurement and is now independently sourced.

Corroborated 2026-09-02 by two sources that fail differently — frankb-a9's
measurement against FPC, and a grep of our own definitions:

```
compiler/defs.inc:1097:  IR_SET_COPY = 40;  { ... copy full 32-byte set }
compiler/defs.inc:2003:    tySet,           { 21: Set — 32-byte bitset }
```

**The width is not in a table someone can widen.** It is in the type kind's own
definition and in an IR opcode's documented contract. 115 `tySet` sites; 39
`IR_SET_COPY`/`IR_SET_LIT` sites.

## What makes it hard, and what does not

Not hard: no value is wrong. Every set operation produces the right answer at 32
bytes, on every target, which is exactly why nothing has caught it — a
differential probe on set *behaviour* passes.

Hard: the size is part of the **by-value ABI class**. A set narrower than 32
bytes is passed and returned differently, so this is not a front-end mapping
change. `IR_SET_COPY` and `IR_SET_LIT` both carry the constant in their
contract and every backend implements them.

## Relation to the umbrella

Wired to [[umbrella-sizeof-is-one-answer]] as the one member where the size
oracle is **not** the defect — `TypeSlotSize(tySet)` is honest about what pxx
builds. This is the case where **the layout itself is the thing to change**,
which is worth having inside the umbrella precisely because it is the opposite
shape: fixing the oracles cannot touch it, and it would otherwise look done when
they are.

## Prio

`prio: 30` is its own intrinsic worth — a real efficiency defect, no wrong value,
no program blocked. It inherits p75 from the umbrella, which is the number that
should route it.
