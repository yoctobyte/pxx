---
track: C
prio: 80
type: bug
blocked-by: []
status: done
summary: "`sizeof(m[0])` on `int m[3][4]` answers 4, not 16 — so `memcpy(dst[1], src[1], sizeof(src[1]))` copies ONE element instead of the row, and `sizeof(a[0])/sizeof(a[0][0])` answers 1 instead of 4. Silent, no cast or pointer arithmetic in sight, and it is wrong on a plain global array — not a struct-field defect. A second, different wrong answer (8) comes back for the unparenthesised form through a field."
status: working
owner: frankC
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

## Root — there were TWO sizeof implementations, and the good one had already published this bug

`ParseCSizeof` served the two spellings from two different mechanisms:

| spelling | mechanism | multi-dim rule |
| --- | --- | --- |
| `sizeof a[0]` (no parens) | a **type-descriptor walk** — *"walked as a type descriptor rather than per-shape special cases, so the chain composes to any depth"* | yes |
| `sizeof(a[0])` (parens) | its own per-shape copy: a `.`-chain walk and a `[` arm | **none** |

So one parenthesis decided whether `memcpy` copied a row or an int.

And the descriptor walk's own comment names the exact failure its twin had:

> *"Without the spans `sizeof m[0]` would answer the element size and
> ARRAY_SIZE(m) would count 15 rather than 3."*

Written by someone who understood the bug completely, in the arm that did not
have it. **Grep for the incumbent before building** — and note this is the worst
version of that rule: a search for the symptom lands on that comment and reads
it as *handled*, because it genuinely was handled, just not on the path the
user's parenthesis takes.

The second defect had the same shape one level down. The walk bailed to the
pointer-size default for a multi-dim record field, on the stated grounds that
*"the spans of a multidim RECORD FIELD are not reachable by symbol index"* —
**a correct sentence justifying a wrong default.** True of symbol indices;
`RecFieldArrDimSpanAt` already existed. That bail is the 8-for-int-char-double.

## Fix (DONE)

1. The descriptor walk asks `RecFieldArrDimSpanAt` for a record field's spans
   instead of bailing.
2. The walk is extracted as `CSizeofDescriptorWalk` and the parenthesised path
   routed through it, **deleting 107 lines** — the whole second implementation.

`compiler/cparser.inc` is ~100 lines shorter and one `sizeof` implementation
lighter. The overhaul was the smaller job, as
`devdocs/dev/root-cause-over-microfix.md` says it usually is.

## Gate — MET

- `make compiler/pascal26` — `converged after 1 round(s)`, `b5bd32802ac8`.
- **All 19 `sizeof` tests in `test/` pass.** That was the real risk: 107 deleted
  lines in an area carrying eight cited ticket fixes — integer-promotion
  sizeof, array member through a pointer, array compound literal, array-type
  extent, unparenthesised subscript, VLA-via-alloca, member chain through a
  pointer, and paren index.
- All four probes match gcc, including both motivating idioms and the
  `int`/`char`/`double` widths.
- **Census re-run** (`tools/c_array_shape_census.py`): the `sizeof` and
  `sizeof-row` rows are now `ok` across all six spellings, 33 wrong cells down
  to 28, nothing regressed. That includes `sizeof(garr[0].m)`, which answered
  **224** (the whole struct) and was listed as a separate open item — the
  normalisation fixed it without a patch of its own, which is the argument for
  normalising rather than patching, arriving as a measurement.
- 219-test named C differential against a reference compiler rebuilt from the
  committed tree — **not** the older baseline, which by now predates two of my
  own fixes and would have produced disagreements that were all real and none
  of them this change's. *An instrument has to be capable of being right, not
  just of disagreeing.* Result: **210 of 210 buildable binaries byte-identical,
  zero output changes**, 9 negative tests neither compiler builds.

  For a 107-line deletion that changes what `sizeof` answers, byte-identical
  everywhere is not "safe" — it is the **third** demonstration tonight that this
  shape has no coverage. `test/csizeof_partial_index_row.c` is now the only
  thing standing between it and the next regression, which is why its 24
  assertions include the widths (`int` and `double`, not just `char`, whose row
  is 8 bytes and therefore indistinguishable from a pointer) and both idioms.

- New regression `test/csizeof_partial_index_row.c`, wired into `test-core`:
  **17 of its 24 assertions fail on the pre-fix compiler**, including
  `sizeof(gm)/sizeof(gm[0])` answering 12 for a 3-row array — precisely the
  failure the surviving walk's comment had predicted in writing.

## Log
- 2026-08-30 — found by the census, fixed by deletion (frankC).

## Related
- [[refactor-c-one-array-shape-reader-instead-of-four-ident-field-pairs]] — the census that found it
- [[bug-c-a-multidim-array-field-decays-with-the-element-stride]]
- [[bug-c-a-struct-field-partial-index-uses-the-outer-row-stride]]
- 2026-08-30 — resolved, commit 8172e6c8e.
