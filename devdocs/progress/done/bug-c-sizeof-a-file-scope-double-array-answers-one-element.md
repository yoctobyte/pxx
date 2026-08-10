---
track: C
prio: 70
type: bug
summary: "sizeof() on a file-scope double[] whose length comes from its initializer answers 8 (one element) instead of the array size — silently, and the int[] case is correct, so nothing looks wrong"
status: done
owner: claude-C
---

# `sizeof` a file-scope `double[]` sized by its initializer answers one element

- **Type:** bug (silent wrong answer) — **Track C** (`compiler/cparser.inc`,
  file-scope array decl)
- **Found:** 2026-08-10, writing the gcc differential probe for
  [[bug-c-pascal-math-names-hijack-libc-through-pxxcio]]. The probe's
  `#define NA (int)(sizeof(ARGS)/sizeof(ARGS[0]))` evaluated to **1**, so it
  swept one argument instead of 38 and reported a clean diff. Caught only
  because the output was 34 lines where gcc's was 8322.

## Measured

```c
#include <stdio.h>
static double A[] = {1.0, 2.0, 3.0, 4.0, 5.0};
static int    B[] = {1,2,3,4,5};
int main(void){ printf("A=%d B=%d el=%d\n",
  (int)sizeof(A), (int)sizeof(B), (int)sizeof(A[0])); return 0; }
```

| | gcc | pxx |
| --- | --- | --- |
| `sizeof(A)` — `double[5]` | **40** | **8** |
| `sizeof(B)` — `int[5]` | 20 | 20 |
| `sizeof(A[0])` | 8 | 8 |

The **int** case is right and the **double** case is wrong, which is what makes
this expensive: the idiom is universal, and the one form that breaks is the one
that looks identical to the form that works. The element size is right, so the
length is what is lost — the declared array is behaving as if it had one element.

## Why the priority is not low

`sizeof(arr)/sizeof(arr[0])` is *the* C array-length idiom. Answering 1 does not
crash and does not warn: every loop over the array silently runs one iteration.
A test written this way passes while testing nothing — which is exactly what
happened here, and the probe was checking a bug fix, so a green probe would have
blessed unverified code.

Suspect the same root as the note already in `lib/crtl/src/stdlib.c`
("a static double array would also trip the C global float-array init gap") —
file-scope *float* array initializers are already known to be a weak spot, so
this may be the length half of one defect. Check `sizeof` on a file-scope
`float[]`, a `double[N]` with an EXPLICIT length, and a local (block-scope)
`double[]` before assuming the boundary.

## Gate

The probe above matching gcc, plus a regression test under `test/` and the C
suites green.

## Resolved 2026-08-10 — and it was worse than filed

**Boundary first** (probe vs gcc, all ten forms). Broken: file-scope
implicit-size **float and double** only. Correct: `int`/`char`/`short`/`long`
implicit-size, `double[5]` explicit, `double[5]` uninitialised, and BOTH
block-scope `double[]` and `float[]`. So the axis is (file-scope × implicit
size × floating-point), not "float arrays" and not "sizeof".

**The suspected shared root with the float-array-init gap was wrong.** That gap
(`bug-c-stb-sprintf-float-empty`, fixed) was the flat-init *emission* path being
ordinal-only. This is the *length inference*, a different site — the earlier fix
taught the emitter about floats and left the sizer ordinal-only, which is why
explicit `double[N]` initialises fine and only the unsized form breaks.

**Not just `sizeof`.** The array is genuinely ALLOCATED one element, so:
`sizeof` answers one element, only `[0]` of the initializer is stored, and the
array **overlaps the next global** — measured `A[1]` returning `Z[0]`'s value,
and `A[4] = x` writing over a neighbour. Silent out-of-bounds read AND write on
legal C, which would have justified a higher prio than 70 had it been filed
that way.

**Root cause:** `compiler/cparser.inc:7124` — the unsized-array length
inference guarded its brace-counting arm on `TypeIsOrdinal(baseTk)`. A float
base type matched no arm and fell through to `else arrLen := 1` (line 7157).

**Fix:** widen that guard to `TypeIsOrdinal(baseTk) or TypeIsFloat(baseTk)` and
pass `TypeIsFloat(baseTk)` as `CBraceFlatIntInitCountAt`'s `allowFloat` (the
scanner already had the parameter; only the ordinal caller existed).

**Test:** `test/cfloat_global_array_implicit_len_b386.c` — returns 42 under gcc
and HEAD, returns 1 under `pinned` with the exact symptom (`A n=1`), so it is a
real control, not a test that merely passes. Covers `double[]`, `float[]`, int
elements into a double array, a `[k]=` designator sizing the array, and the
neighbour-overlap case. Deliberately a NEW file: the sibling
`test/cfloat_global_array_init_b197.c` covers only explicit-size forms — that
is precisely why it never caught this — and overwriting it would have destroyed
the coverage it does carry.

**Found while verifying, filed separately, PRE-EXISTING (reproduces identically
on `pinned`, so not from this fix):**
`bug-c-cast-of-a-float-element-array-to-a-pointer-yields-a-wrong-address`.

Gate: `make compiler/pascal26` fixedpoint converged, repro matches gcc,
`tools/gate.sh quick` GREEN.

## Log
- 2026-08-10 — resolved, commit PENDING-COMMIT.
