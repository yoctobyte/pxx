---
prio: 55  # auto
---

# C ptrdiff of &-expressions: `&x[1] - &x[0]` wrong stride

- **Type:** bug (C→IR pointer-diff lowering). Track C.
- **Found:** 2026-07-06 c-testsuite run.

## Failing test
- 00037: `&x[1] - &x[0] != 1` (int x[2]) — diff not divided by element size
  when an operand is an AN_ADDR node (IRPointerStride has no AN_ADDR branch).

## WARNING — failed fix attempt (reverted 2026-07-06)
Previous session added an AN_ADDR branch to IRPointerStride in ir.inc taking
stride = size of the addressed expr's type via `IntToTypeKind(ASTTk[inner])`.
That fixed 00037 but REGRESSED test-core `test/cglobal_array_elem_addr_b133.c`
(exit 2: `wp - wide` for `const u16 *wp = &wide[204]` came out wrong — ASTTk of
the inner node is not reliably the element type on that path). Hunk reverted.
A correct fix must derive the element type the same way the AN_INDEX lowering
does, and must keep BOTH 00037 and b133 green.

## Gate
Drop 00037.c from test/c-conformance/pxx.skip; make test-c-conformance AND
make test-core green.

## Retry 2026-07-07 — reverted again, root cause pinned
Retried with a BETTER stride derivation (for `&base[i]`, stride =
IRPointerStride(base) via the reliable Syms element type, NOT ASTTk[inner] which
defaults to int for narrow arrays). This made 00037 pass AND standalone u16/char
`&a[i]-&a[j]` correct — but b133 STILL regressed (exit 2, `wp - wide != 204`).

Root cause pinned: `IRPointerStride` on an AN_ADDR node is called in TWO
contexts with conflicting needs:
1. ptrdiff `&x[1] - &x[0]` — needs the element size (4 for int).
2. b133's GLOBAL-INIT address `const u16 *wp = &wide[204]` — relies on the old
   fall-through value; giving it the real element stride breaks wp's computed
   value.
So the real fix must DISENTANGLE these: the ptrdiff lowering should compute the
element stride from the addressed base directly (not via IRPointerStride(AN_ADDR)),
leaving the global-init-address path's IRPointerStride(AN_ADDR) untouched — OR
the global-init path must stop routing through IRPointerStride. Find where the
`&wide[204]` global initializer calls IRPointerStride and split the two. Track A
(shared ir.inc), focused session. b133 is in test-core, so the gate guards it.


## RESOLVED 2026-07-07 (Track A+C, sole-A)
IRPointerStride had no AN_ADDR branch, so `&x[1] - &x[0]` used stride 1 (byte
diff, = sizeof(int)) instead of 1. Added an AN_ADDR case: for `&arr[i]` the
pointee is arr's element, so the stride is the INDEXED BASE's own stride — derived
by recursing IRPointerStride on ASTLeft[AN_INDEX], NOT from the AN_INDEX node's
ASTTk (the prior attempt's approach, which regressed `&wide[204]` where wide is a
`const u16*`). Recursing on the base handles both array and pointer bases
uniformly. Other &-forms keep the size-1 default. 00037 matches, b133 stays green,
dropped from pxx.skip -> c-conformance 196/0. Regression b175. self-host
byte-identical.
