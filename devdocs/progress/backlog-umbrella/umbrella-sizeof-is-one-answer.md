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
  - bug-p-a-string-n-element-loses-its-capacity-in-three-container-shapes
  - bug-p-sizeof-answers-pointer-width-for-a-string-n-that-occupies-more
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
stride of 18. A subrange wider than 32 bits was this shape too and is
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

## Wiring a member — the edge runs ONE WAY

**The UMBRELLA carries `blocked-by: <member>`. A member must NOT carry
`blocked-by: <umbrella>`.** Written the second way it means what it says — the
ticket is blocked BY the umbrella — and `ready` drops it entirely, which is the
exact opposite of joining the queue. Measured 2026-09-02: three tickets were
wired backwards (this coordinator told frankb-a9 to do it, and did it itself on
the set split); all three vanished from `ready` at p75 and nothing errored.
Add your slug to the list above instead.

## What the three C members actually were (measured 2026-09-02, all three closed)

`bug-c-a-file-scope-pointer-to-array-crashes-on-indexing` (`7d6559cd3`),
`...-struct-field-answers-the-pointer-size` (`1769ac004`) and
`...-reaches-a-pointee-through-one-spelling-only` (`536a3e2d0`).

**They were not three bugs.** Two of them are ONE arm in two scopes: the
parenthesised-declarator path, written for function pointers — whose pointee
genuinely has no type — and reached by `int (*p)[4]` as well, because
`ParseCDeclType` parks the name in `CTypeFnPtrName` for both shapes. It
recorded no pointee at file scope and none on a struct field; the local path
records one and has always worked. Three copies, one of them right.

**This umbrella's framing survives but its C example did not.** The recorded
`sizeof(*s.fp)` = 8 "the arm never firing at all" was already stale: it
answered **4**, and 4 is not the element size either — it is
`TypeStorageSize(tyUnknown)`, i.e. nothing recorded. The `int` spelling cannot
tell those apart, because the unknown default equals `sizeof(int)`. It took
`double (*dp)[4]` answering 4 rather than 8 to separate them. **Every C row in
this family that is spelled with `int` is a guard that cannot fail**, and the
same trap sits in the Pascal members: a size row whose expected value
coincides with a default proves nothing. Rows here must use a type whose size
is not 4 and not `sizeof(void*)`.

The third was a different mechanism and worth separating from the other two:
the token walk `CSizeofDescriptorWalk` answered `TypeSlotSize(tyUnknown)` and
reported success, while the general expression path — which typed the operand
correctly all along — was locked out because the walk had consumed the operand.
That is not "too few parameters"; it is a PARALLEL path answering where it
should decline, and the residue is banked as
[[bug-c-the-sizeof-descriptor-walk-answers-from-tyunknown]]. It belongs to this
umbrella's thesis all the same: it is one more thing that was asked how big a
type is and answered.

One new column was needed: `UFldPtrElemArrLen`, the field twin of
`SymPtrElemArrLen`. That is shape 1 exactly — `TypeStorageSize(kind, recId)`
cannot express "array pointee of extent N", so the extent had to be threaded to
the caller instead. **A fifth oracle was NOT added**; the existing readers were
given the parameter they were missing.

## One member was removed, deliberately

`bug-a-a-set-is-32-bytes-whatever-its-bounds-and-the-ir-opcode-says-so` was
wired here and is **unwired as of 2026-09-02**, parked to `rainy-day/` by the
owner. It was always the odd member — the one case where the size oracle is
NOT the defect, since `TypeSlotSize(tySet)` is honest about what we build.
With the width chosen, it cannot be delivered by fixing the oracles, so
leaving it as a blocker would make this umbrella permanently unreachable.
**A parked member blocks the goal forever; that is why the edge is gone rather
than merely annotated.**

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
