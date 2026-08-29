---
track: C
prio: 80
type: bug
blocked-by: []
summary: "`sizeof(m[0])` on `int m[3][4]` answers 4, not 16 — so `memcpy(dst[1], src[1], sizeof(src[1]))` copies ONE element instead of the row, and `sizeof(a[0])/sizeof(a[0][0])` answers 1 instead of 4. Silent, no cast or pointer arithmetic in sight, and it is wrong on a plain global array — not a struct-field defect. A second, different wrong answer (8) comes back for the unparenthesised form through a field."
---

# sizeof of a partial index answers the element, not the row

- **Type:** bug (SILENT wrong value, silent data loss) — **Track C**.
- **Found:** 2026-08-30 (frankC), by the executable census for
  [[refactor-c-one-array-shape-reader-instead-of-four-ident-field-pairs]].

## Why prio 80 — above the segfaults in the sweep

A segfault is loud. This truncates a copy and returns.

```c
int src[3][4], dst[3][4];
memcpy(dst[1], src[1], sizeof(src[1]));
```

| | gcc | pxx |
| --- | --- | --- |
| `dst[1]` after the memcpy | `10 11 12 13` | **`10 -1 -1 -1`** |
| same through a field, `s.m[2]` | `20 21 22 23` | **`20 -1 -1 -1`** |
| `sizeof(src[0]) / sizeof(src[0][0])` | 4 | **1** |

Both are *the* idiomatic C spellings — size a row copy from the row, count a
row's elements by dividing the sizes. Neither involves a cast, a pointer, or a
struct. The last line is the one that will quietly halve a loop bound somewhere
in a corpus.

## Two different defects, found by varying the shape

The census reported one wrong cell; an isolated probe disagreed with it, and
separating the parenthesis from the spelling showed **two** mechanisms with two
different wrong answers:

| form | gcc | pxx |
| --- | --- | --- |
| `sizeof m[0]` (bare, ident) | 16 | 16 — **correct** |
| `sizeof(m[0])` (parens, ident) | 16 | **4** |
| `sizeof gs.m[0]` (bare, field) | 16 | **8** |
| `sizeof(gs.m[0])` (parens, field) | 16 | **4** |
| `sizeof m` / `sizeof(m)` (whole array) | 48 | 48 — correct |

- **4** is the element size: the partial index is being measured as if it
  yielded an element rather than a row.
- **8** is a pointer, and that is measured rather than inferred: the bare
  through-a-field form answers **8 for every element type** — `int m[3][4]`
  wants 16, `double d[2][3]` wants 24, and both come back 8, while
  `char c[2][8]` returns 8 and looks correct by coincidence. A row measured as
  a pointer, not as an element.
- The parenthesised form is wrong **even for a plain global ident**, where
  every other construct in the census is right.

## Why nothing found this before — and it is the point of the sweep's method

This is the case a grep for the duplicated-arm pattern is structurally unable
to find. There is no correct sibling arm to notice the absence against:
`sizeof(m[0])` is wrong for an ident *and* a local *and* a field *and*
`p->m` *and* a nested field. **A search for divergent copies cannot find logic
that is missing everywhere** (frankS, 2026-08-29, from the xtensa
`ABIParamSlotHoldsValueAddr` case — the backend that needed converting was the
one with zero copies of the pattern).

It fell out of the enumeration on the first run, because a behavioural cell is
wrong whether the code that should handle it is divergent or absent.

## Note on the measurement

The census harness spells every cell parenthesised, so its `sizeof-row` row
reported `16!=4` across all six spellings and read as one universal defect. An
isolated probe using the bare form contradicted it. Both were right about
different things; the grid above is what separating the two variables shows.
**A census cell that disagrees with a hand probe is a signal to vary the shape,
not to pick a winner.**

## Gate

`sizeof` in all four combinations above, plus the `memcpy` and the
`sizeof/sizeof` element count, matched against gcc; a new test wired into
`test-core`; `make compiler/pascal26` byte-identical; the 219-test named C
differential explained.

## Related
- [[refactor-c-one-array-shape-reader-instead-of-four-ident-field-pairs]] — the census that found it
- [[bug-c-a-multidim-array-field-decays-with-the-element-stride]]
- [[bug-c-a-struct-field-partial-index-uses-the-outer-row-stride]]
