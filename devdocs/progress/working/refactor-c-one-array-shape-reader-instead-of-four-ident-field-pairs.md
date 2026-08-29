---
track: C
prio: 75
type: refactor
blocked-by: []
summary: "Four C readers ask what a decayed array steps by, and all four are written as an AN_IDENT branch beside an AN_FIELD branch. Three field branches were never finished: five ordinary expressions SEGFAULT (`**a.s`, `*(*(a.m+1)+2)`, `strcmp(*(a.s+1),\"cd\")`), one loads four bytes of a char row. Three of the pairs were repaired one at a time on 2026-08-29; this replaces the shape with one reader so there is no fifth pass."
status: working
owner: frankC
---

# One array-shape reader, instead of four ident/field pairs

- **Type:** refactor that closes open SEGFAULTs — **Track C**, spanning
  `compiler/cparser.inc` (C) and `compiler/ir.inc` (**A**, needs the A slot).
- **Scoped by frank-coordinator, 2026-08-29**, after three separate field-arm
  bugs landed in one day.

## The census — 2026-08-30 (frankC), 116 cells measured, 33 wrong

Run as an **enumeration, not a pattern search**, on frankS's rule: *a search
for duplicated logic cannot find the place where the logic is missing.* Every
one of the three field-arm bugs fixed on 2026-08-29 was found by grepping for
the pattern just fixed, so the same blind spot would have shaped this census.

So the list is defined by the language, not by the codebase: **every way C can
reach an array** (spelling) crossed with **everything C can do with one**
(construct), one standalone program per cell, gcc deciding each. A cell is
wrong whether the code that should handle it is divergent *or absent*, and it
cannot tell the difference — which is the property the rule demands and a
reading of the four routines could never have.

```
construct       global-ident  local-ident  struct-field  ptr-arrow  nested-field  elem-of-array
row-stride      ok            ok           ok            ok         ok            ok
row-stride-2    ok            ok           ok            ok         ok            ok
partial-elem    ok            ok           ok            ok         ok            ok
partial-elem-2  ok            ok           ok            ok         ok            ok
noop-deref      ok            ok           SIGSEGV       SIGSEGV    SIGSEGV       SIGSEGV
deref-plus      ok            ok           SIGSEGV       SIGSEGV    SIGSEGV       SIGSEGV
deref-partial   ok            ok           ok            ok         ok            ok
sizeof          ok            ok           ok            ok         ok            48!=224
sizeof-row      16!=4         16!=4        16!=4         16!=4      16!=4         16!=224
ptrdiff         ok            ok           4!=1          4!=1       4!=1          4!=1
row-var         ok            ok           ok            ok         ok            ok
row-into-fn     ok            ok           ok            ok         ok            ok
row-into-ptr    ok            ok           ok            ok         ok            ok
char-load       ok            ok           99!=25699     99!=25699  99!=25699     99!=25699
char-noop-deref ok            ok           SIGSEGV       SIGSEGV    SIGSEGV       SIGSEGV
char-strcmp     ok            ok           SIGSEGV       SIGSEGV    SIGSEGV       SIGSEGV
char-row-stride ok            ok           ok            ok         ok            ok
3d-stride       ok            ok           ok            ok         -             -
3d-partial      ok            ok           SIGSEGV       SIGSEGV    -             -
3d-all-star     ok            ok           SIGSEGV       SIGSEGV    -             -
3d-row-var      ok            ok           ok            ok         -             -
```

**What the enumeration found that the pattern search could not.** The
`sizeof-row` row is wrong on **every** spelling, `global-ident` included —
there is no correct sibling arm anywhere to notice its absence against. It is
filed separately at prio 80, because it is worse than every segfault in this
grid: `memcpy(dst[1], src[1], sizeof(src[1]))` copies one element instead of
the row and returns normally, and `sizeof(a[0])/sizeof(a[0][0])` answers 1
instead of 4. See
[[bug-c-sizeof-a-partial-index-answers-the-element-not-the-row]] — and note
that its grid needed a *second* measurement: the census spells every cell
parenthesised, an isolated bare-form probe disagreed, and separating the two
variables showed two mechanisms with two different wrong answers. **A census
cell that disagrees with a hand probe is a signal to vary the shape, not to
pick a winner.**

**Confirmed-correct readers, recorded so nobody sweeps them a fifth time.**
Eleven constructs are right across all six spellings: `row-stride` (both),
`partial-elem` (both), `deref-partial`, `row-var`, `row-into-fn`,
`row-into-ptr`, `char-row-stride`, `3d-stride`, `3d-row-var`. Four of those
six spellings — `gp->m`, `gs.in.m`, `garr[0].m`, and the local — had **never**
been probed before today, and the two fixes of 2026-08-29 generalise to all of
them without further work. That is the enumerate-the-correct-ones instruction
paying for itself: those cells are now evidence, not assumption.

**Still open from the grid** (beyond the `sizeof` ticket): the segfault family
(`noop-deref`, `deref-plus`, `char-noop-deref`, `char-strcmp`, `3d-partial`,
`3d-all-star`) on all four non-ident spellings; `ptrdiff` answering 1 instead
of 4 through a field; `char-load` reading four bytes of a `char` row; and
`sizeof(garr[0].m)` answering 224 (the whole struct) instead of 48.

## The evidence that makes this prio 75 and not a tidy-up

```c
struct A { char s[2][8]; int m[3][4]; int t[2][3][4]; } a;
```

| expression | gcc | pxx |
| --- | --- | --- |
| `**a.s` | 97 | **SIGSEGV** |
| `*(*(a.m+1)+2)` | 12 | **SIGSEGV** |
| `*(*(a.t[1]+2)+3)` | 9 | **SIGSEGV** |
| `*(*(*(a.t+1)+2)+3)` | 9 | **SIGSEGV** |
| `strcmp(*(a.s+1), "cd")` | 0 | **SIGSEGV** |
| `*a.s[1]` | 99 (`'c'`) | **25699** (loaded 4 bytes of a char row) |

Every one of these, written against a file-scope array instead of a struct
field, is correct **and has a passing assertion in
`test/carr2d_decay_stride.c` today**. The array column is pinned line by line;
the field column was never looked at.

## The shape

One question — *what is this node's array shape: rank, element type, element
size?* — asked by four readers, each written as "if AN_IDENT … else if
AN_FIELD":

| reader | file | AN_IDENT arm | AN_FIELD arm |
| --- | --- | --- | --- |
| `ParseCPostfixTail` partial index | `cparser.inc` | correct | **fixed** `10676bcc2` |
| `IRPointerStride` | `ir.inc` **A** | rank>=2 -> row stride | **fixed** (this day) |
| `CDerefDecayStride` | `cparser.inc` | walks to the ident, answers the level | **`Exit` (0)** — the segfaults |
| `CNodePointeeTk` AN_BINOP arm | `cparser.inc` | element type of the array | **falls to `tyInteger`** — the 25699 |

`CDerefDecayStride` answering 0 for a field means the no-op deref of a
pointer-to-array emits a real LOAD: the row's first eight bytes are read as an
address and dereferenced. That is precisely the failure
[[bug-c-deref-of-a-pointer-to-array-loads-instead-of-decaying]] describes and
fixed — for idents only.

## GREP FOR THE INCUMBENT BEFORE BUILDING — 2026-08-30 (frankC)

**This ticket proposed to build two things that already existed.** Both were
found by looking for the incumbent before writing code, and neither was found by
the census, the grep, or reading the routines the ticket names. It is the
finding, not the preamble:

| the ticket wanted to build | what was already there | why nobody used it |
| --- | --- | --- |
| a shared array-shape reader | `NodeArrNDInfo` — ident, field **and** deref-of-pointer-to-array | its caller guards it with `ASTKind[node] = AN_IDENT` |
| a multi-dimension rule for `sizeof` | the `sizeof` **type-descriptor walk** | it served only the *unparenthesised* spelling |

The second is the worse of the two and worth stating on its own, because it
defeats a search for the symptom rather than merely surviving one. The surviving
`sizeof` walk's comment reads:

> *"Without the spans `sizeof m[0]` would answer the element size and
> ARRAY_SIZE(m) would count 15 rather than 3."*

**Written by someone who understood the bug completely, in the arm that did not
have it.** A grep for the symptom lands on that comment and reads it as
*handled* — and it genuinely was handled, just not on the path a parenthesis
takes. [[bug-c-sizeof-a-partial-index-answers-the-element-not-the-row]] closed
it by deleting the second implementation: 107 lines gone, `cparser.inc` ~100
lines shorter, and the census's `sizeof` **and** `sizeof-row` rows green across
all six spellings. `sizeof(garr[0].m)` answering 224 — the whole struct — was
listed here as a separate open item and needed no patch of its own; the
normalisation took it. **That is the argument for normalising rather than
patching, arriving as a measurement instead of a principle.**

Census after that fix: **28 wrong cells, down from 33, nothing regressed.**

## The accessor already exists, and one caller filters out half of it — 2026-08-30 (frankC)

Found before writing any code, by asking frankS's question instead of mine
(below). **`NodeArrNDInfo` (`compiler/pasparser_call.inc:483`) is already the
shared reader this ticket proposes to invent.** It fills `NDInfoNDims` /
`NDInfoLo[]` / `NDInfoSpan[]` and it already handles all three shapes — an
`AN_IDENT` array, an **`AN_FIELD`** array, and an `AN_DEREF` of a
pointer-to-array. Its own header says so: *"Lets m[..], r.m[..] and p^[..]
share one path."*

`ParseCPostfixTail` calls it — and gates the call:

```pascal
if (ASTKind[node] = AN_IDENT) and NodeArrNDInfo(node) then   { cparser.inc:3714 }
```

**That guard is the bug generator.** It excludes exactly the shape the helper
already supports, which is why a second, near-identical struct-field arm exists
180 lines below re-deriving everything from `RecFieldArrNDims` /
`RecFieldArrDimSpanAt` / `RecFieldRowStride` — the arm that carried both defects
fixed in `10676bcc2` and that nothing downstream could then answer for.

So the shape is not "four readers grew divergent copies". It is: **one shared
reader exists, one caller declines to use half of it, and a duplicate arm grew
in the gap.** That reframes the work from *invent an accessor* to *delete a
guard and collapse what it forced into existence*, which is the smaller job and
the one that removes cases instead of adding them.

Two real gaps remain in the accessor, and they are what the C readers actually
need on top of spans and lows:

1. It fires only for **rank >= 2** (`>= 2` in all three arms), so a 1-D array
   answers False — but `long long v[8]` reached as a field is exactly one of the
   shapes that was broken.
2. It yields rank/lows/spans but **not the element type, element record or
   element size** — which is precisely the part each reader re-implements per
   node kind.

`NodeArrNDInfo` lives in `pasparser_call.inc` = **Track P's file**, so do not
extend it under Track C. The C-side answer is a thin `CNodeArrayShape` in
`cparser.inc` that calls `NodeArrNDInfo` for rank/spans and adds the element
triple with **one** ident/field switch — four switches become one, in C's own
lane, with no Track P edit and no new symtab surface.

## Why one reader, not two more patches

`root-cause-over-microfix.md` asks for tickets-closed-per-change, not lines
touched. Three of these four pairs have now been repaired individually, each
time by someone who had just read the correct arm sitting directly above the
broken one and did not notice. **The two arms being adjacent in the same
routine is what makes the bug survive review**: every fix looks local and
complete, and nothing in a diff shows the sibling going unedited — a reviewer
sees a correct change to correct code (frank-coordinator). Put the other way:
**three agents did not skip the grep; the diff never gave them a reason to run
it** (frankC).

The second sentence is the one that picks the remedy. A discipline failure is
answered with a reminder, and reminders do not work. Review blindness is
answered structurally — one reader instead of an IDENT/FIELD pair — which is
what this ticket proposes.

So introduce one `CNodeArrayShape(node)` answering *(rank, element type,
element size, dim spans)* for an ident, a field, and anything else that decays,
and route all four readers through it. Three duplicated branches disappear and
the fifth instance becomes unwritable.

**Enumerate all four in the resolution, including any that turn out already
correct** — *"a reader confirmed correct is the only thing that stops a fifth
pass"* (frank-coordinator). `refactor-c-string-literal-decay-belongs-at-the-producer`
is plausibly the same family; check it before scoping.

## Gate

- A new test covering the six expressions above, matched against gcc, plus the
  existing `carr2d_decay_stride.c` / `cfield_partial_index_stride.c` /
  `cll_array_pointer_base.c` unchanged.
- `make compiler/pascal26` byte-identical; the 219-test named C differential
  explained, not merely accepted.
- Needs the **Track A slot** for `IRPointerStride`. The `cparser.inc`
  three-quarters could land alone, but landing half a normalisation leaves two
  readers keyed on the old shape, so land it as one piece.

## Related
- [[bug-c-a-multidim-array-field-decays-with-the-element-stride]] (the stride pair, fixed)
- [[bug-c-a-struct-field-partial-index-uses-the-outer-row-stride]] (the parser pair, fixed)
- [[refactor-c-the-partial-index-sentinel-should-not-be-a-type-tag]] (how all of it surfaced)
- [[normalise-dont-special-case]] — three landed instances, no longer a prediction
