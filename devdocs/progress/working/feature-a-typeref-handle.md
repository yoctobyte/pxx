---
track: A
prio: 65
type: feature
---

# TypeRef: one type handle, carried — not ten parallel tuples

Design: `devdocs/dev/type-identity-as-substrate.md` item 1.

## What

~90+ distinct sites store "which type is this". They are not 90 concepts — they
are the SAME ~8-field tuple redeclared per entity kind:

```
SymPtrBaseTk/Rec   AliasPtrBaseTk/Rec   UFldPtrElemTk/Rec
ProcRetPtrElemTk/Rec   CTypeFnRetPBaseTk/Rec   LiftCapPtrTk/Rec
```

and again for `*Tk`, `*Rec`, `*ElemTk`, `*ElemRec`, `*ProcSig`, `*DynDepth`,
`*ArrLen`. Symbols alone carry ~26. A bug is simply one of them not written —
four such bugs landed in one session.

This is a COLLAPSE of existing duplication, not a new representation. That is
what makes it survivable under the self-host gate.

## Payoff beyond the bug class

`project_tsymbol_field_landmine` ("no new TSymbol fields") and
`project_symtab_alloc_parallel_array_landmine` ("Alloc* must reset ALL fields")
are symptoms: the record could not absorb more, growth went to parallel arrays,
and a recycled slot now carries stale identity unless every array is reset. With
one struct that reset is a single assignment that cannot be half-forgotten.

## Landing rule

**Additively.** Introduce `TypeRef` with nothing reading it, migrate consumers
lane by lane behind existing gates. Do NOT cut over — this sits under
byte-identical self-host.

Blocks [[feature-a-abi-oracle]] (the oracle takes a TypeRef).
