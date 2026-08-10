---
track: C
prio: 60
type: bug
summary: "Casting an array with a FLOAT element type to a pointer — `(void*)a` — yields a wrong address (a stack address for a file-scope array), while the same array decays correctly when passed to a parameter and int arrays are correct in both forms"
---

# `(void*)` on a float-element array yields a wrong address

- **Type:** bug (silent wrong value) — **Track C** (C frontend, array decay
  under an explicit cast)
- **Found:** 2026-08-10, verifying the fix for
  [[bug-c-sizeof-a-file-scope-double-array-answers-one-element]]. The verifying
  probe printed `%p` for the array and the number was neither the array's
  address nor stable.
- **Pre-existing:** reproduces **identically** on
  `stable_linux_amd64/default/pinned`, so it is not a regression from that fix.
  Controlled that way rather than reasoned about.

## Measured

```c
#include <stdio.h>
static double A[] = {1.5,2.5,3.5,4.5,5.5};
static int    B[] = {1,2,3,4,5};
void show(const char *t, void *p){ printf("  %s via param: %p\n", t, p); }
int main(void){
  double L[4];
  printf("cast (void*)A : %p\n", (void*)A);
  printf("bare      &A[0]: %p\n", (void*)&A[0]);
  printf("cast (void*)B : %p\n", (void*)B);
  printf("local (void*)L : %p\n", (void*)L);
  show("A", A); show("B", B); show("L", L);
  printf("A==&A[0]: %d  B==&B[0]: %d\n",
         (void*)A == (void*)&A[0], (void*)B == (void*)&B[0]);
  return 0;
}
```

| form | element type | gcc | pxx |
| --- | --- | --- | --- |
| `(void*)A` file-scope | `double` | `&A[0]` | **stack address** (`0x7fff…`) — wrong |
| `(void*)B` file-scope | `int` | `&B[0]` | `&B[0]` — correct |
| `(void*)L` block-scope | `double` | `&L[0]` | **differs from `&L[0]`** — wrong |
| `A` passed as a `void*` parameter | `double` | `&A[0]` | `&A[0]` — **correct** |
| `A == &A[0]` | `double` | 1 | **0** |
| `B == &B[0]` | `int` | 1 | 1 |

## The boundary

Two axes, both needed to reproduce: the element type must be **floating-point**,
and the decay must happen under an **explicit cast** rather than by being passed
to a parameter of pointer type. Scope does not matter (file-scope and
block-scope are both wrong), which distinguishes this from the sizeof bug above,
where scope was the deciding axis.

`A == &A[0]` answering **0** is the sharpest form: the two sides of an identity
C guarantees disagree, with no diagnostic.

## Why it matters

The cast form is how C code hands an array to `memcpy`, `qsort`, `fwrite`,
`write`, or any `void*` API. A double array passed that way writes to, or reads
from, an address that is not the array. That is silent memory corruption in
ordinary, legal code — not a diagnostic-level issue.

Suspect the float-typed rvalue path converting the array *value* (a load of
element 0, or a temporary spilled to the stack) instead of taking the array's
address before the cast — the stack address in the file-scope case points that
way. **That is a lead to disprove, not a diagnosis**; establish it by reading
the emitted IR (`PXXDBG=a.ir:main`) before changing code.

## Gate

The probe above matching gcc on every row (address equality, not just
"looks like a pointer"), a regression test under `test/`, and the C suites
green. Check the same shape for a `float[]` and for a cast to `double*` /
`char*`, not only `void*`.
