---
prio: 60
resolved: fb342151
---

# bug: scalar pointer-global initializers silently skipped (null pointer at runtime)

- **Track:** C (cfront)
- **Found:** 2026-07-14 by the csmith differential fuzzer (seed 3, PXX_CRASH), while
  closing [[bug-c-csmith-seed2-segfault]]. Filed already-fixed — the board is the record.

## What was wrong
A scalar pointer global whose initializer the fast paths in `ParseCGlobalVarDecl`
could not fold was **silently skipped** — the pointer stayed null and the first
dereference segfaulted (at -O0, gcc fine). Broken shapes:

```c
static char *p1 = (char*)&g;   /* cast + address-of */
static int  *p3 = &st.a;       /* &struct.field     */
static int  *p5 = arr + 1;     /* pointer arithmetic */
```

`&g`, `&arr[k]`, string literals were fine (dedicated fast paths).

## Fix (fb342151, b351)
Unfoldable scalar pointer inits defer to a **replay at main** (new `CScalInit*`
table beside the aggregate walker's `CAggInit*`): re-seek the expression token,
`ParseCExpr` + `CompileAST` an assignment — the same machinery function bodies
use. Regression test `test/cglobal_scalar_ptr_init_defer_b351.c` (output
byte-identical to a gcc-built binary's), wired into test-core.

Sibling of the same family: [[bug-c-csmith-seed2-segfault]] (1-D pointer-ARRAY
initializers, b350).
