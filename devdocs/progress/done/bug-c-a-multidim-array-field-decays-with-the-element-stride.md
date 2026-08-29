---
track: C
prio: 75
type: bug
blocked-by: []
summary: "A multi-dim array reached as a struct FIELD decays with the ELEMENT stride, not the ROW stride: `(char*)(s.m+1)-(char*)s.m` on `int m[3][4]` answers 4 where gcc says 16 (1 for a char row, 8 for a double row), and `int (*r)[4] = s.m+1; r[0][2]` silently reads a different element. IRPointerStride's AN_IDENT arm has the row rule; its AN_FIELD arm, one screen below in the same routine, never got it."
status: done
owner: frankC
---

# A multi-dim array FIELD decays with the element stride

- **Type:** bug (silent wrong value) — **Track C** defect, **Track A file**
  (`compiler/ir.inc`, `IRPointerStride`'s AN_FIELD arm), held under the grant in
  [[refactor-a-c-exclusive-lowering-has-no-carved-out-file-so-track-c-cannot-be-staffed]].
- **Found:** 2026-08-29 (frankC), writing the regression test for
  [[refactor-c-the-partial-index-sentinel-should-not-be-a-type-tag]] — the last
  assertion in it was the only one that still failed after that refactor.

## Measured (gcc oracle)

```c
struct A { int m[3][4]; char c[2][8]; double d[2][3]; } s;
```

| expression | gcc | pxx before |
| --- | --- | --- |
| `(char*)(s.m+1) - (char*)s.m` | 16 | **4** |
| `(char*)(s.c+1) - (char*)s.c` | 8 | **1** |
| `(char*)(s.d+1) - (char*)s.d` | 24 | **8** |
| `int (*r)[4] = s.m + 1; r[0][2]` (with `s.m[1][2]=7`) | 7 | **0** |

The bare-array spelling of every one of these is correct and pinned by
`test/carr2d_decay_stride.c`. The last row is the one that matters: no cast, no
visible pointer arithmetic — a row pointer assigned and read back, answering a
different element.

## Root

`IRPointerStride`'s AN_IDENT arm carries the C rule for rank >= 2 — a multi-dim
array decays to a pointer to its ROW, so the stride is the element size times
the product of the remaining dims
([[bug-c-a-multidim-array-decays-with-the-element-stride]]). Its AN_FIELD arm,
one screen below **in the same routine**, answered `RecFieldType` and stopped.

`RecFieldRowStride` already computes exactly the needed value and
`ParseCPostfixTail` already calls it, so the fix is four lines: for
`RecFieldArrNDims > 1`, answer `RecFieldRowStride` and exit.

## Why this keeps happening

The **third** field-arm defect found on 2026-08-29 whose array-arm twin was
fixed months earlier:

| the array arm got | the field arm did not | fixed |
| --- | --- | --- |
| the `ASTSLen` stamp on a decayed row | — | `10676bcc2` |
| the product-of-remaining-spans multiplier | — | `10676bcc2` |
| the multi-dim ROW decay stride | — | **here** |

That is not bad luck; it is `normalise-dont-special-case.md` with three landed
instances instead of a prediction. **What makes it expensive is that the two
arms are adjacent in the same routine** — so every fix *looks* local and
complete, and nothing in a diff shows the sibling going unedited. A reviewer
sees a correct change to correct code (frank-coordinator, 2026-08-29). Put the
other way: three agents did not skip the grep; the diff never gave them a
reason to run it.

Two further readers are built the same way and are **worse than this one** —
they segfault. Enumerated, with the sweep that should replace all four:
[[refactor-c-one-array-shape-reader-instead-of-four-ident-field-pairs]].

## Fix (DONE)

`compiler/ir.inc`, `IRPointerStride`'s AN_FIELD arm: when the field is a
multi-dim array, answer `RecFieldRowStride` and exit, exactly as the AN_IDENT
arm does.

## Gate — MET

- `make compiler/pascal26` — `converged after 1 round(s)`.
- `test/cll_array_pointer_base.c` (new, wired into `test-core`): 16 assertions
  over `long long` decay as ident and as field, 1-D and 2-D, plus pointer
  difference. Passes; matched against gcc; failed 6 assertions before the
  sentinel refactor and 1 after it.
- The three-element-type probe above matches gcc for `int`, `char`, `double`.
- 219-test named C differential, pre/post, sha256 of each binary: 209
  identical, 0 output changes, 1 binary changed (`carr2d_decay_stride`, the
  sentinel refactor's dead-code removal, explained separately), 9 that
  **neither** compiler builds — six deliberate negative tests
  (`cconst_negative_array_bound_fails`, `c_pasunit_ansistring_fail`,
  `c_pasunit_ansistring_result_fail`, `cstray_toplevel_reject_b193`,
  `cundeclared_fnptr_arg_rejected_b167`, `cundeclared_type_cast_fail`) and
  three needing flags a bare invocation does not pass
  (`crtl_string_leaf_b130` wants `-I`, `cvararg_many_args_b135`,
  `cvararg_overflow_b93`). Both compilers reject all nine identically: those
  are unmeasured cells, not passes, and 209/219 would have handed the reader a
  denominator including ten things it never measured.

  **This fix changed ZERO binaries in that set.** For a change that alters an
  emitted stride constant, that is not reassurance — it is proof that no
  existing test reaches a decayed multi-dim array field at all, which is why
  four element types were wrong and nothing said so. The same thing was true of
  [[bug-c-a-struct-field-partial-index-uses-the-outer-row-stride]] earlier the
  same day. The field spelling of this whole family is uncovered.

## Log
- 2026-08-29 — found, fixed, tested (frankC). Ownership of `ir.inc` granted and
  filed on master at `25de2c21d`; `tools/fleet_dirt.sh` across 16 checkouts
  confirmed no other lane held the file.
- 2026-08-30 — resolved, commit 72de20420.
