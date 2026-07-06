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
