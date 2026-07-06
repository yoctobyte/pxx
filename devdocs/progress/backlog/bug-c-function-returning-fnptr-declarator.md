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

## Pinned 2026-07-07
00089 core reduced: `typedef int (*fty)(void); fty go(void){...}` -> CERR
"expected C expression". A LOCAL `fty f = &zero;` works (ParseCLocalDeclAST has
the CTypeFnPtrName inline-fnptr branch). ParseCSubroutine's return-type path
(retType := ParseCDeclType at cparser.inc:5013) does NOT handle a fnptr-typedef
return type — after consuming `fty` (tyPointer + CTypeProcSig set), the name/param
reading derails. Fix: mirror the local fnptr-typedef handling for a function's
RETURN type (register `go` with retType tyPointer + the fnptr proc signature, read
name+params normally). 00124 separately needs the inline full declarator
`int (*f(int,int))(int,int)`. Bounded-ish declarator work, focused session.

## Further pinning 2026-07-07 — a fnptr-typedef declarator cluster
Probed the fnptr-typedef (`typedef int (*fty)(void)`) in several positions:
- `fty go(void);` (prototype) — WORKS (pass-1 registration is fine).
- `fty go(void){ return &z; }` (definition) — CERR "expected C expression" in the
  BODY (the proto registers, but compiling the body of a fnptr-typedef-returning
  function derails).
- `fty gp = &z;` (global variable) — CERR "call to undeclared function: gp" (a
  fnptr-typedef-typed GLOBAL isn't registered either).
- `myint go(void)` (non-fnptr typedef return) — WORKS.
So it's a cluster of fnptr-typedef declarator gaps (function-definition body,
global-var decl) beyond the original 00089/00124, all rooted in how a tyPointer +
CTypeProcSig "callable" type flows through the def/global paths. Focused session.
