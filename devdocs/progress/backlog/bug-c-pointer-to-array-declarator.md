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

## Triage note (2026-07-06)
Confirmed not a quick fix: needs a real "pointer whose element is an array" type (element = array-of-N, stride N*elem) plus 2-D stride through it for `p[i][j]`. The `(*p)[4]` declarator, the decay `p = arr`, and the double index all depend on that type existing. Codegen ICE "Unsupported linear node Kind=10" is the AST for the unmodelled type reaching codegen. A dedicated modeling change, not a patch.

## Confirmed 2026-07-07
Even the bare declarator `char (*p)[4];` fails to PARSE ("expected C expression")
— the `(*name)[N]` pointer-to-array declarator isn't recognized at all, and the
pointer-to-array TYPE (element = array-of-N, stride N*elem) isn't modelled. Needs
both a declarator-parser addition and the type representation. Deep; focused
session.

## Assessment 2026-07-08 (a-agent) — confirmed a modeling session, scoped
Not started (released without holding). Concrete shape after the array-typedef
work: `char (*p)[4]` = a POINTER whose element is a fixed array-of-4. Needs, in order:
1. **Declarator parse** `(*name)[N]` — mirror the existing fn-ptr `(*name)(...)`
   branch in ParseCDeclType (CTypeFnPtrName path); capture N.
2. **Symbol shape** — a new field e.g. `SymPtrElemArrLen` (and dim span for the
   multi-`[N][M]` case) on the pointer symbol: "the pointee is an array of N".
   No existing field carries this (PtrElemTk is scalar-only).
3. **Index lowering, two sites** — `p[i]` must (a) LOAD p's value (it is a
   pointer variable, unlike an array whose address is used directly), then (b)
   stride by `N*elemSize` and yield an ARRAY-typed lvalue so the following `[j]`
   indexes within. Reuse the 2-D flat-stride math but with the first "dimension"
   coming from a pointer deref, not a fixed dim.
4. **Decay assignment** `p = arr` — a 2-D array (`SymArrNDims=2,[2,4]`) decays to
   `char(*)[4]`: assign arr's base address, carry the row length 4 onto p.
`q = &arr[1][3]` and `*v` already work (scalar element addr / plain deref).
The ICE "Unsupported linear node Kind=10" today is the unmodelled AST reaching
codegen. Peer of the fn-ptr declarator + the multidim array stride code; ~one
focused session. Corpus payoff is modest (rare idiom) — prio stays 55.
