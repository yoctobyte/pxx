
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
