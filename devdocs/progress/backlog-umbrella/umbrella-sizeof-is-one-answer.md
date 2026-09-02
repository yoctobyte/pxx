---
slug: umbrella-sizeof-is-one-answer
track: A
prio: 75
type: umbrella
status: backlog
owner: ""
blocked-by:
  - compat-pascal-four-type-sizes-disagree-with-fpc-and-every-value-agrees
  - bug-p-sizeof-rejects-twelve-type-names-that-a-declaration-accepts
  - bug-p-a-user-type-whose-name-shadows-a-builtin-is-unusable
  - bug-c-sizeof-of-a-pointer-to-array-struct-field-answers-the-pointer-size
  - bug-c-sizeof-reaches-a-pointee-through-one-spelling-only
  - refactor-a-the-const-cast-width-table-is-the-third-copy
  - bug-n-nilpy-carries-its-own-copies-of-the-float-type-table
  - bug-a-pascal-nilpy-rust-and-zig-over-align-an-8-byte-member-on-i386
  - bug-a-method-pointer-record-is-hard-sized-16-bytes-on-32-bit-targets
summary: "GOAL: a program can trust SizeOf. `FillChar(x, SizeOf(x), 0)` and `Move(a, b, SizeOf(a))` are correct for EVERY type in every frontend, and `file of T` can write a layout that reads back. Today they are not: SizeOf answers 8 for every `string[N]` while pxx's OWN layout engine gives that type 18, so `FillChar` on an `array[0..2] of string[10]` clears 24 of 54 bytes and leaves a[2] intact -- silent, and correct under FPC so no differential probe sees it. Root cause is measured and structural: FOUR functions answer `how big is this type`, each adding one more parameter because the kind alone was not enough -- TypeSlotSize(tk) at 363 sites, TypeStorageSize(tk, recId), SizeOfSlot(tk, cap), FrozenStrSlotSize(tk, cap). SizeOfSlot's own comment says it: `A FROZEN STRING'S SIZE IS NOT A FUNCTION OF ITS KIND`. Two is a smell, three is a design flaw; this is four, plus duplicated builtin type tables in A, N and P that disagree with each other."
---

# Umbrella: `SizeOf` is one answer

**The goal is a property a program can rely on**, not a refactor: `FillChar(x,
SizeOf(x), 0)` zeroes all of `x`, `Move(a, b, SizeOf(a))` copies all of `a`, and
a record written by `file of T` reads back. Those are the commonest idioms in
Pascal and they are wrong today for ordinary declared types.

## Why this is one umbrella and not nine tickets

Measured 2026-09-02. Four functions answer *how big is this type*, and each was
added when the previous one's parameters turned out to be insufficient:

| function | parameters | sites |
| --- | --- | --- |
| `TypeSlotSize` | kind | **363** |
| `TypeStorageSize` | kind + record id | — |
| `SizeOfSlot` | kind + capacity | — |
| `FrozenStrSlotSize` | kind + capacity | 15 |

`SizeOfSlot`'s own comment states the defect: *"TypeSlotSize, except that **A
FROZEN STRING'S SIZE IS NOT A FUNCTION OF ITS KIND**."* The model is wrong —
size is a property of a TYPE, and every one of these takes a KIND plus whatever
extra the author needed that day. `root-cause-over-microfix.md`: two mechanisms
for one concept is a smell, three is a design flaw. **This is four**, and beside
it sit duplicated builtin type-name tables in A, N and P that disagree.

Every member below is the same sentence in a different place: **something other
than the layout engine was asked how big a type is, and it answered.**

## Two shapes

**1. The oracle takes too few parameters** — so a type whose size depends on
more than its kind is silently wrong. `SizeOf(string[N])` = 8 against a real
stride of 18; C's `sizeof(*s.fp)` for `int (*)[4]` = 8 where gcc says 16, the
arm never firing at all. A subrange wider than 32 bits was this shape too and is
**fixed** (`ffe20a8bc`) — `-3000000000` read back as `1294967296`, and nine days
of probes missed it because every one used a range that happened to fit.

**2. Duplicated type tables that disagree** — `ConstIntCastWidth` is the THIRD
copy of the builtin table; `pyparser.inc` holds three private copies of the
float mapping; Pascal settles a builtin name against the TABLE rather than
against the PROGRAM, so a user type shadowing a builtin answers `12 8 8` for the
same `SizeOf` in one program.

## What ENDS this umbrella

One oracle, asked by everything, answering from a type rather than a kind — and
a test that a value assertion cannot pass by accident. **The assertion class
matters here**: a wrong size does not corrupt a value in the common case, it
mis-sizes a copy, so `expect_same` rows pass while `FillChar` leaves a tail
intact. The subrange bug was found only because its positive control was a SIZE
row rather than a value row. Any test this umbrella accepts must assert sizes
and strides directly, and must include a row where the type's size is NOT a
function of its kind.

## Notes

- **`prio: 75` was set by the coordinator, not the owner** — he said the SizeOf
  bugs are worth doing and to work them as a group. It is above
  `feature-pascal-typed-and-untyped-files` [p70], which cannot be correct until
  layout is, and below the two live p85 umbrellas. Change it freely; per
  CLAUDE.md the umbrella number is the one a human sets.
- Members keep their own tracks and gates. This spans A, C, N and P by
  construction — that is the finding, not an accident of filing.
- frankb-a9 has a `string[N]` ticket drafted from the measurement above; wire it
  here when it lands.
