---
track: A
prio: 35
type: bug
blocked-by: []
summary: "_Generic over an array controlling expression now decays correctly for scalar, record and multi-dim elements (measured equal to gcc), but two element shapes still select the wrong association: `int *p[2]` answers `default` where gcc answers `int **`, and `const int ci[2]` answers `int *` where gcc answers `const int *`. Both need a carrier the array symbol does not have — the element's POINTER TARGET and the element's CONSTNESS — so neither is fixable at the descriptor site. Two rows of a seven-row gcc differential; the other five match."
status: open
owner: ""
---

# `_Generic` on an array loses the element's pointer target and its constness

- **Type:** bug (C frontend — type descriptors) — **Track A** (`cparser.inc`,
  shared descriptor machinery), tag **C**.
- Found 2026-09-01 by frankA while closing
  [[audit-a-typekind-tyrecord-is-not-a-guard-against-an-array-symbol]], which
  gave `CExprCG` its first array arm. These two rows are what that arm cannot
  reach; they are filed rather than guessed at.

## The differential, `gcc -std=c11` against `pascal26` on one file

`before` is the compiler at `e4d4f945961e` (no array arm at all), `after` is
`a7e7f780b782`.

| controlling expr | gcc | before | after |
| --- | --- | --- | --- |
| `struct S a[3]` | `struct S *` | `default` | `struct S *` |
| `int b[4]` | `int *` | `int` | `int *` |
| `char c[5]` | `char *` | `char` | `char *` |
| `long L[2]` | `long *` | `long` | `long *` |
| `int m[2][3]` | `default` | `int` | `default` |
| **`int *p[2]`** | **`int **`** | `int *` | **`default`** |
| **`const int ci[2]`** | **`const int *`** | `int` | **`int *`** |
| `struct S one` (control) | `struct S` | `struct S` | `struct S` |
| `int scal` (control) | `int` | `int` | `int` |

The five fixed rows are pinned by `test/cgeneric_array_decay.c` (wired into
`test-core`). **The two open rows are deliberately NOT in that file**: a test
that asserts a wrong answer teaches the next reader that the wrong answer is
intended. They are here instead, with the oracle command, so whoever takes this
starts from a measurement.

Repro (the two rows alone):

```c
#include <stdio.h>
int main(void){
  int *p[2]; const int ci[2];
  puts(_Generic(p,  int **:"i**", int *:"i*", default:"?"));   /* gcc: i**  pxx: ?  */
  puts(_Generic(ci, const int *:"ci*", int *:"i*", default:"?")); /* gcc: ci* pxx: i* */
  (void)p;(void)ci; return 0;
}
```

## Why the array arm cannot answer them

`CExprCG`'s array arm builds the element descriptor from what the SYMBOL
carries: `Syms[sym].ElemType`, `Syms[sym].ElemRecName`, `SymCLongRank[sym]`,
and `SymArrNDims`/`SymArrDimSpan` for the inner dimensions. That is enough for
a scalar, a record and a multi-dim element, and it is the whole of what the
symbol has.

- **`int *p[2]`** — `ElemType` is `tyPointer`, and the element's *pointee* is
  not recorded anywhere. A non-array pointer symbol has `PtrElemTk` /
  `PtrElemRec` / `SymPtrDepth`; the ELEMENT of an array has no equivalent. So
  the descriptor is a `cgPtr` with no sub, which matches neither `int **` nor
  `int *`, and the selection falls to `default`. (Before the array arm it
  answered `int *` — also wrong, and wrong in the more dangerous direction,
  since a confident wrong association compiles into a wrong call.)
- **`const int ci[2]`** — element constness is not recorded either.
  `CGConstA` exists on the descriptor and `CGConvControlling` correctly drops
  only the TOP-level const, so the machinery downstream is ready; the fact
  simply never reaches it.

So both are the same shape: **a carrier that exists for a scalar symbol and has
no array-element twin.** That is the thing to fix — a `SymElemPtrElemTk` /
`SymElemPtrElemRec` / `SymElemConst` set, threaded where `SymElemDynDepth`
already is — not a special case at the descriptor site.

## Ranked 35 deliberately

`_Generic` on an array of pointers or a const array is rare in real C, and the
five common rows are now correct. Ranked by how much real code reaches it, per
the compat rule. What raises it is a corpus program selecting wrongly, and the
probe above is the thing to re-run then.

## What a fix must assert

- both rows above equal `gcc -std=c11` on the same file
- the five rows already in `test/cgeneric_array_decay.c` stay equal to gcc
  (they are the control: a carrier added in the wrong place would move them)
- the two non-array controls (`struct S one`, `int scal`) stay equal — a fix
  that pushes every symbol through an element path would break these and
  nothing else watches them
- `tools/gcc_diff_probe.sh` rather than a hand-written expectation, so the
  oracle is not a transcription
