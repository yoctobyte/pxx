---
prio: 55  # auto
---

# C functions returning function pointers: typedef'd return type + full declarator

- **Type:** bug (cparser declarators). Track C.
- **Found:** 2026-07-06 c-testsuite run.

## Failing tests
- 00089: `typedef struct S *(*fty)(); fty go() {...}` — definition with typedef'd
  fnptr return type apparently not registered: caller gets "call to undeclared
  function: go". Call chain `go()()->zerofunc()` (call result of call).
- 00124: full declarator form `int (*f1(int a, int b))(int c, int d) {...}` —
  COMPILES but exit 85: call `(*(*p)(0, 2))(2, 2)` returns garbage → returned
  fnptr or the double indirect call miscompiled.

## Gate
Drop 00089.c/00124.c from test/c-conformance/pxx.skip; runner green.

## Triage note (2026-07-06)
00089: `fty go()` where `fty` is a typedef for a fn-pointer — `go` is not registered as a function ("call to undeclared function: go"), so the fn-def detector mis-handles a typedef-fnptr RETURN type (likely treats `go` as a fn-pointer variable via the typedef proc-signature). 00124: full inline declarator `int (*f1(int,int))(int,int)` compiles but the double-indirect call returns garbage (85). Both are C declarator-grammar work (function returning function pointer), a focused session.
