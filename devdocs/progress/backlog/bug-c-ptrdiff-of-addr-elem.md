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
