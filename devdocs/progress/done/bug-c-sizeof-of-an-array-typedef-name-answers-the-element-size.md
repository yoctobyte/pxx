---
slug: bug-c-sizeof-of-an-array-typedef-name-answers-the-element-size
track: C
prio: 40
type: bug
blocked-by: []
status: done
found: 2026-09-05
found-by: frankC
owner: unassigned
summary: "FIXED 2026-09-05 (frankC). ParseCSizeof's type-name arm never consulted the typedef's recorded dimensions, so sizeof of an ARRAY TYPEDEF NAME answered the ELEMENT size (double 8 vs gcc 32, char 1 vs 4, int 4 vs 16) while sizeof of a VARIABLE of the same typedef was already correct. IT WAS THE VISIBLE EDGE OF SOMETHING WORSE: chasing it found that CTypedefArrLen held only the FIRST dimension, so multi-dim array typedefs were under-allocated and indexed with the wrong stride, corrupting neighbouring locals -- fixed in the same commit (bug-c-a-multi-dimensional-array-typedef-is-half-modelled-and-corrupts-neighbouring-locals). The test keeps all THREE element widths deliberately: 8 is also TypeSlotSize(tyUnknown) and the double row alone cannot separate this from bug-c-the-sizeof-descriptor-walk-answers-from-tyunknown, which is where the first reading sent it."
---

# `sizeof` of an array typedef name answers the element size

## Measured

Binary `9048792b2dc3`, gcc as the oracle, one program:

```c
typedef double TA[4];   sizeof(TA)   gcc 32   pxx 8
typedef char   TC[4];   sizeof(TC)   gcc  4   pxx 1
typedef int    TI[4];   sizeof(TI)   gcc 16   pxx 4
```

Ablated against `10492cae86d8` (the same tree with the
pointer-to-typedef'd-array fix stashed out): identical, so this is **not** a
regression from that work — that work is merely what was measuring nearby when
it turned up.

## What still works, which is what makes it narrow

Same typedef, same program:

- `sizeof(gplain)` where `TA gplain;` -> **32**, correct.
- `sizeof(gs)` where `TA gs[2];` -> **64**, correct.
- `gs[0][0]` and `gs[1][3]` read and write correctly.

So `CTypedefArrLen` is recorded and the declarator paths consume it. The defect
is confined to the operand being the **type name** rather than an object.

## Read this before assuming it is the tyUnknown walk

The first reading of this was that it is
[[bug-c-the-sizeof-descriptor-walk-answers-from-tyunknown]], whose signature is
`sz := TypeSlotSize(tyUnknown)` = **8** — and `sizeof(TA)` for the `double`
typedef answers **8**. The two are indistinguishable on that row, because
`sizeof(double)` and the pointer default are both 8.

**The `char` and `int` rows separate them in one command.** A tyUnknown default
answers 8 for all three; the observed answers are 8 / 1 / 4, tracking the
ELEMENT size exactly. Different mechanism, different fix.

This is the "choose a probe whose right answer differs from the default" rule
paying out: a `double` element collides with the pointer width, and the
collision produced a confident wrong diagnosis that was one measurement away
from being written into the wrong ticket.

## For whoever takes it

Start from `ParseCSizeof`'s type-name arm and ask where a typedef's
`CTypedefArrLen` is consulted — the declarator paths in `ParseCLocalDeclAST`
and `ParseCGlobalVarDecl` both read `CTypeTypedefArrLen`, and the type-name
operand path appears not to. Assert all three element widths, not just one, for
the reason above.

## Log
- 2026-09-05 — resolved; this names the commit that carried the resolve, which is not always the one that carried the change — commit 5435c14a7.
