---
track: C
prio: 45
type: bug
blocked-by: []
summary: "`*f() = x` calls f TWICE — for a scalar destination as well as a struct one. Found beside bug-c-quickjs-runner-segfaults..., which fixed the struct half of the LHS double-lowering; this shape survives it and predates it."
---

# `*f() = x` evaluates the call on the left TWICE

- **Track C** (C frontend / IR lowering of an assignment destination).
- Found 2026-08-20 while fixing
  [[bug-c-quickjs-runner-segfaults-with-zero-output-on-the-full-smoke-js]],
  by the probe that found that one. **Not the same defect**: that one was the
  struct destination being lowered twice for the assignment's VALUE, and this
  shape is wrong for a SCALAR destination too, where no such re-lowering
  happens.

## Repro

```c
#include <stdio.h>
static int calls;
static long long lbuf[8];
static long long *lbump(void) { calls++; return &lbuf[0]; }

int main(void) {
  calls = 0; *lbump() = 5;
  printf("%d\n", calls);   /* gcc 1, pxx 2 */
  return 0;
}
```

The struct-destination form (`*sbump() = v`) does the same, and still does
after the quickjs fix.

## Why it matters

C guarantees the destination expression is evaluated exactly once. A function
call on the left is not exotic — allocator-and-store idioms
(`*next_slot() = x`) and container APIs use it, and the failure is a **doubled
side effect with a correct value**, which no output comparison catches. The
whole C corpus (lua, sqlite, tcc, zlib, quickjs) missed the struct half of this
family until a csmith checksum found it; expect the same here.

## First move

`PXXDBG=a.ir:main` on the repro and look for the call node appearing twice —
that is how the struct half was read off. If the call node is emitted once as
a statement and again as an operand, it is the same emitter shape the RHS
ticket describes ([[bug-c-a-struct-assignment-used-as-a-value-runs-its-rhs-twice]]),
and the answer is likely a temp rather than a reuse.

## Gate

The repro matches gcc; the destination-side-effects test under `test/` gains
the `*f() = v` case; C tests green + self-host byte-identical.
