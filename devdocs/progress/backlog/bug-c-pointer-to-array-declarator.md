---
prio: 55  # auto
---

# C pointer-to-array declarator `char (*p)[4]` hits IR "Unsupported linear node"

- **Type:** bug (cparser declarator + C→IR lowering). Track C.
- **Found:** 2026-07-06 c-testsuite run.

## Failing test
- 00130: `char arr[2][4], (*p)[4]; p = arr; ... p[1][3]` — ICE:
  "Unsupported linear node in IR codegen! Kind=10 node=10 IRA=1 IRB=-1 IRC=-1 IRIVal=0"
  at line 2. Pointer-to-array type (row stride 4) not representable; indexing
  through it needs stride = array size.

## Gate
Drop 00130.c from test/c-conformance/pxx.skip; runner green.
