
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
