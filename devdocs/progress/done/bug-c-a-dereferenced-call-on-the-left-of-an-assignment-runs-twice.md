---
track: C
prio: 45
type: bug
blocked-by: []
summary: "`*f() = x` calls f TWICE — for a scalar destination as well as a struct one. Found beside bug-c-quickjs-runner-segfaults..., which fixed the struct half of the LHS double-lowering; this shape survives it and predates it."
status: done
owner: frank1-ACP
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


## What it was — TWO mechanisms, both about emitting one node twice

Measured against gcc, not reasoned: `PXXDBG=a.ir` on `void f(void){ *lbump() = 7; }`
showed ONE call node in the IR, so the doubling was in the emitter, not the
lowering. The correct sibling `lbump()[0] = 7` differed in exactly one bit —
its call node carried `ival=0` and the broken one `ival=1`, the
"statement-level: side-effect call" marker the top-level emit loop keys on.

**1. Discarded (statement, or a comma's left operand).** C's "an assignment is
an expression yielding the stored value" rule appends a load-back after the
store. At statement level that load is dead, and `IRDiscardValue` — whose job is
to keep a discarded expression's calls from becoming orphans — marked the
load's ADDRESS operand as a statement. For `*f() = v` that address IS the call,
and the store_mem already dragged it in, so it was emitted twice. The struct
form did the same one level up, where the discarded root is that call node
itself.

Fixed by giving `IRDiscardValue` the AST node it is discarding and returning
immediately for an `AN_ASSIGN`: an assignment always emits its own statement
root (store_sym / store_mem / copy_rec / var_store), and that root drags the
whole destination and value tree with it. Nothing there ever needs marking.

**2. Consumed (`t = (*f() = 6)`, `w = (*sbump() = v)`).** The IR is emitted by
walking each statement root's operand tree with **no value cache**, so a node
reachable from two roots runs twice — here the store_mem is one root and
whatever consumes the load-back is the other. The comment left by the quickjs
fix, that "one node with two consumers is emitted once", is only true while one
of those consumers is INSIDE the other; this shape is the counterexample and
the comment is now corrected in place.

Fixed with `IRLowerDestAddress`: when the destination address contains a call
(`IRAddrMayCall`, a kind-aware walk — IRA is a node index for some opcodes and a
symbol index for others), park it in a pointer temp. The store fills it once and
the loads that replace it are pure. Both helpers are C-mode-only, so Pascal's
self-build stays byte-identical.

All four destination shapes now agree with gcc — scalar and struct, discarded
and consumed — and the index/field forms that were already right are pinned
against regression. quickjs's smoke is still byte-exact.

## What it was NOT — the compound form is a different bug

`*f() += 1` still calls f twice, and so does every compound assignment with a
side-effecting lvalue (`a[i++] += 1`, `*p++ += 1` steps p by TWO). That is not
this defect: cparser desugars `x OP= y` into `x = x OP y` **reusing the same
AST node**, so the frontend hands the lowering two independent copies of the
lvalue and no IR-level sharing can help. Filed with the measurements and a
recommended design as
[[bug-c-a-compound-assignment-evaluates-its-lvalue-twice]] (prio 60).
The increment operators are already correct — `AN_INCDEC` lowers the address
once — which is the model that ticket should follow.

## Log
- 2026-08-20 — resolved, commit PENDING-COMMIT.
