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
