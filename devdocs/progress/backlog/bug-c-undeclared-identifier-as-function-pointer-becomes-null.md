---
summary: "C: an undeclared identifier used where a function POINTER is expected becomes 0 with only a warning — the program then jumps to null"
type: bug
track: C
prio: 45
---

# An undeclared identifier passed as a callback compiles to NULL and segfaults

- **Type:** bug (C frontend — **Track C**)
- **Opened:** 2026-07-31 by Track B, building the gcc-oracle differential for
  [[feature-crtl-implement-libc-assumptions]]. The census test tripped over it,
  which is how it was found rather than reasoned about.

## Repro

```c
#include <stdio.h>
#include <stdlib.h>
static int arr[] = {1,3,5,7};
int main(void) {
  int cmp(const void *x, const void *y) { return *(const int*)x - *(const int*)y; }
  int key = 5;
  int *hit = (int*)bsearch(&key, arr, 4, sizeof(int), cmp);
  printf("%d\n", hit ? *hit : -1);
  return 0;
}
```

```
gcc:  5
pxx:  pascal26:2115: warning: undeclared identifier 'cmp' used as value (treated as 0)
      ok: ...
      Segmentation fault
```

## Two things, and the second is the one that matters

1. **`cmp` is a GNU nested function.** That is an extension, not ISO C, so not
   supporting it is a defensible position — gcc accepts it and real code
   occasionally uses it, but that is a scope call.

2. **An undeclared identifier used as a FUNCTION POINTER becomes `0`, with a
   warning, and the program then calls through null.** That is the part that
   is wrong regardless of what is decided about (1). "Treated as 0" is a
   reasonable recovery for an undeclared *value* — it is not a reasonable one
   for something being passed where a callee will `call` it, because the
   diagnostic is a warning that scrolls past and the consequence is a segfault
   somewhere else entirely.

The same "treated as 0" recovery is what silently turned `M_SQRT2` into `0`
in [[bug-crtl-headers-lost-when-cwd-is-not-the-repo-root]] — same mechanism,
different victim. There it produced a wrong number; here it produces a crash.

## Shape

The cheap and correct minimum, independent of nested functions: when an
undeclared identifier is used in a context whose target type is a POINTER (a
function-pointer parameter especially), make it a hard ERROR rather than a
warning-plus-zero. A program that would jump to null is not one worth emitting.

Supporting GNU nested functions is a separate, larger question — they need a
trampoline or a lifted closure — and should be its own ticket if a corpus
actually demands it. Note this repro does NOT need them: the same code with
`cmp` at file scope compiles and matches gcc exactly, and that is the form
`test/crtl_libc_oracle.c` uses.

## Gate

C tests green + self-host byte-identical, plus a regression asserting the
repro above is REJECTED rather than built.
