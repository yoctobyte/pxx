---
track: C
prio: 70
type: bug
summary: "sizeof() on a file-scope double[] whose length comes from its initializer answers 8 (one element) instead of the array size — silently, and the int[] case is correct, so nothing looks wrong"
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
