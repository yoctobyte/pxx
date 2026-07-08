---
prio: 55  # auto

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

## Progress 2026-07-07 — two sub-fixes landed; remaining gaps pinned
Resolved parts of the cluster (both gated, self-host green):
- fn-pointer TYPEDEF global `fty gp = &z;` — commit a386edce (register callable +
  bind init).
- `go()()` — calling the result of a function that returns a function pointer —
  commit cfebdbbb (new ProcRetProcSig + CNodeProcSig AN_CALL case).
Still open for 00089/00124:
- `get()->f()` — calling a fn-pointer FIELD on a call RESULT SIGSEGVs (the field
  fnptr call on a non-lvalue call result).
- 00089's exact form `struct S *(*fty)()` (empty params, struct-ptr return): go
  is reported "undeclared" at the call — its registration differs from the simple
  `int (*fty)(void)` form that now works (likely the empty `()` param list or the
  struct-ptr return in ParseCSubroutine).
- 00124: full inline declarator `int (*f1(int,int))(int,int)` (compiles, runs 85).
Each is a further ParseCSubroutine / postfix-call refinement — focused session.

## 00124 finding 2026-07-07
00124's inline declarator `int (*f1(int,int))(int,int)` PARSES (compiles) — the
remaining issue is the nested double-indirect call `(*(*p)(0,2))(2,2)` mis-lowers
(runs 85, want 0). So both remaining cases are fn-pointer CODEGEN, not parser:
00089 = fnptr-field call on a call result (SIGSEGV); 00124 = chained
deref+indirect-call value. Deep codegen, focused session.

## Deeper layers pinned 2026-07-07 (3 sub-fixes now landed)
Landed this stretch: fnptr-typedef global (a386edce), `go()()` (cfebdbbb),
`&func` struct fn-ptr field init (81400021). Remaining for 00089 isolated to the
fnptr typedef whose return type is a STRUCT POINTER:
- `typedef int (*fty)(); ... go()()` — WORKS (empty params + int return fine).
- `typedef struct S*(*fty)(void); ... go()()->v` — COMPILES but SIGSEGVs: the
  indirect call go()()'s RETURN TYPE (struct S*) isn't tracked, so `->v` on the
  result can't resolve the record. Needs a ProcRetProcSig-analog for the return
  RECORD/type carried through the indirect call.
- `typedef struct S*(*fty)()` (empty params + struct-ptr return) — "go
  undeclared": go isn't even registered — the empty-`()` + struct-ptr-return
  combination in the fn-def path fails registration.
So the last of 00089 is return-type propagation through a fn-pointer indirect
call (+ the empty-param struct-ptr-return registration edge). Deeper; focused.

## Codegen wall 2026-07-07
`go()()->v` (fty = struct-ptr-returning fn pointer) SIGSEGVs in the DOUBLE-
INDIRECT CALL codegen — go()() itself returns a wrong pointer, so ->v derefs
garbage (record resolution is a red herring; adding AN_CALL_IND to ResolveNodeRec
did not help and was reverted). So the last of 00089/00124 is fn-pointer call
CODEGEN: (a) go()() (call-of-call-result) returning a struct pointer, (b) 00124's
`(*(*p)(0,2))(2,2)` chain. Deep backend work — focused session. The three parser-
level sub-fixes (typedef global, go()() parse, &func struct field) are landed.

## Progress 2026-07-08 (a-agent) — 00089 FIXED, 00124 remains
Root cause of 00089 was three-fold, all around a fn-pointer typedef whose RETURN
type is a struct pointer (`typedef struct S *(*fty)();`):
1. **ParseCTypedef routing** — the leading `struct` sent it down the aggregate
   fast-path (`typedef struct Tag *Name;`), which finds `(` instead of a plain
   name and registers NOTHING → `fty` stayed undefined ("stray token"). Added
   `CTypedefAggFnPtrDeclarator` lookahead: a struct/union typedef whose declarator
   is `(*name)(...)` now routes through the general ParseCDeclType path.
2. **Signature lost its result record** — the `$cfnptr` sig registered at the
   fn-ptr declarator never set ProcRetPtrElemTk/Rec, so an indirect call's result
   had no pointed-at record. Now captured before the param recursion and set on
   the sig.
3. **`p()->field` IR gap** — `CNodeIsPointer` had no AN_CALL_IND case, so the
   arrow never wrapped the call result in AN_DEREF and built `AN_FIELD(AN_CALL_IND)`
   → IRLowerAddress hit IR_UNSUPPORTED. Added AN_CALL_IND to CNodeIsPointer and to
   both node-record resolvers (CNodePtrElemTk/Rec).

00089 green. Conformance 209 pass / 0 fail / 11 skip. Self-host byte-identical,
quick tier + lua/core green. Dropped 00089 from pxx.skip.

**Remaining (ticket stays open):** 00124 — `int (*f1(int,int))(int,int)` (a
FUNCTION returning a fnptr, full inline declarator) still compiles but exits 85:
the double-indirect call `(*(*p)(0,2))(2,2)` returns garbage. Separate from the
typedef-fnptr-return path above — a fn-returning-fnptr codegen/declarator bug.
