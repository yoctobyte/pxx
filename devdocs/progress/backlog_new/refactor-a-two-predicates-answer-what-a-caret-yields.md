---
slug: refactor-a-two-predicates-answer-what-a-caret-yields
title: "`NodePtrElem` and `ResolveDerefShape` both answer 'what does `^` yield', and neither is a superset"
track: A
prio: 55
type: refactor
blocked-by: []
status: backlog_new
owner: ""
created: 2026-08-25
summary: "Two functions type a dereference. NodePtrElem knows more SPELLINGS (index-into-base, pointer FIELD, inline PTR_CAST, pointer arithmetic); ResolveDerefShape knows more ABOUT each (remaining depth, ultimate base). Swapping a call site from one to the other trades one kind of knowledge for the other, silently — which is exactly what shipped a regression on 2026-08-25."
---

# The two

| | file | knows |
| --- | --- | --- |
| `NodePtrElem(node, var elemTk, var elemRec, depth)` | `symtab.inc` | the IMMEDIATE pointee, over many node shapes: `AN_IDENT`, `AN_INDEX` (recursing into its base), `AN_FIELD`, `AN_PTR_CAST`, and `AN_BINOP` pointer arithmetic |
| `ResolveDerefShape(node, var tk, var recName, var remDepth, var ptrBaseTk, var ptrBaseRec)` | `pasparser_lval.inc` | the pointee **plus remaining depth and ultimate base**, over `AN_IDENT`, `AN_FIELD`, `AN_INDEX` *(AN_IDENT base only)*, `AN_DEREF`, the call kinds, `AN_PTR_CAST`, and a final else that delegates to `NodePtrElem` |

Neither contains the other. `ResolveDerefShape` is richer per shape and poorer
in shapes.

# What that cost, concretely

`15ec54d7a` moved the alias-cast suffix walk in `pasparser_expr.inc` off
`NodePtrElem` and onto `ResolveDerefShape`, to fix `PPRec(pp)^^.f` resolving
every trailing field at offset 0 — a real fix, and depth is exactly what
`NodePtrElem` cannot give.

It also broke `PRec(raw)^.arr[1]^`, which had been fine: an `AN_INDEX` whose
base is an `AN_FIELD` (a `array[0..2] of PStr` field). `ResolveDerefShape`'s
index arm handles only an `AN_IDENT` base, so it claimed the node, answered
`tyUnknown`, and the walk fell back to the OUTER cast's alias. The test printed
a raw pointer where it had printed `world`
(`regression-test-core-test-cast-deref-chain-siblings`, fixed in `bfb7b4c59` by
having `ResolveDerefShape` ask `NodePtrElem` whenever its own arms came out
`tyUnknown`).

That patch stops the bleeding. It does not stop the next swap.

# Shape of the fix

One function that answers the full triple for every spelling. The cheapest
honest route is to lift `NodePtrElem`'s missing shapes INTO `ResolveDerefShape`
— an `AN_INDEX` over a non-IDENT base, and pointer arithmetic — with the depth
metadata each of them can actually supply, then make `NodePtrElem` a thin
wrapper that discards the depth for the callers that only want the pointee.
Beware: the array-element depth lives in the ARRAY symbol's own
`SymPtrDepth`/`SymPtrBaseTk` slots (see the long note in `ResolveDerefShape`'s
index arm), and a FIELD's in `UFldPtrDepth`/`UFldPtrBase*`; a non-IDENT base has
no such row, which is why that arm gave up in the first place. Widening it may
mean answering "pointee known, depth unknown" explicitly rather than pretending
depth 0.

# Same disease, one type family over

[[refactor-a-two-dyn-array-depth-functions-that-drift]] — `NodeDynDepth` vs
`DynArrayNodeDepth`, same week, same failure mode (a silent wrong VALUE, not an
error). `devdocs/dev/normalise-dont-special-case.md` is the doctrine; here the
double case is two whole functions rather than two arms.

# Gate

Track A: `make compiler/pascal26` (fixedpoint) + `tools/gate.sh quick`. Pinned
by `test/test_cast_deref_chain_siblings.pas`,
`test/test_cast_deref_pointer_field.pas`,
`test/test_pointer_to_a_pointer_through_a_cast_and_a_forward.pas`, and the
`^PChar` shape tests. A full-tier A/B is worth asking Track T for, for the same
reason as the sibling ticket: the failure mode is a wrong value, not a red.
