---
track: A
prio: 40
type: feature
---

# TypeRef: migrate consumers lane by lane

Follow-up to [[feature-a-typeref-handle]], which landed `TTypeRef`
(`compiler/defs.inc`) additively — the record exists, nothing reads it yet.
This ticket is the actual payoff: replacing the ~90+ parallel-array sites
(`SymPtrBaseTk`/`SymPtrBaseRec`, `UFldPtrElemTk`/`UFldPtrElemRec`,
`ProcRetPtrElemTk`, `LiftCapPtrTk`/`LiftCapProcSig`, ...) with one `TTypeRef`
field per entity, one lane at a time.

See `devdocs/dev/type-identity-as-substrate.md` for the full design and why
this matters (the "one of six parallel arrays not written" bug class — four
such bugs landed in one session per that note's evidence table).

## Landing rule (unchanged from the parent ticket)

Each lane migrates ONE entity kind's parallel arrays to a single `TTypeRef`
field, lands under the self-host byte-identical gate, and does not touch any
other lane's arrays in the same change. Candidate lane order (smallest/
lowest-risk first, largest blast radius last):

1. `TSymbol` (`Syms[]`) — the largest single consumer (~26 parallel fields per
   the design note), but also the most self-contained: read/write sites are
   concentrated in `symtab.inc`/`ir.inc`.
2. `AliasPtrBaseTk`/`AliasPtrBaseRec` (type aliases).
3. `UFldPtrElemTk`/`UFldPtrElemRec` (class/record fields).
4. `ProcRetPtrElemTk`/`ProcRetProcSig` (routine return types).
5. `LiftCapPtrTk`/`LiftCapProcSig` (closure capture types).
6. `CTypeFnRetPBaseTk`/`CTypeFnRetPProcSig` (C frontend type declarations).

Each lane: add a `TTypeRef` field alongside the existing parallel arrays,
populate it everywhere the old arrays are populated (do not remove the old
arrays yet — they stay the source of truth until every READ site is migrated
too), then migrate reads, then delete the old arrays once nothing references
them. Land incrementally — this is explicitly NOT a one-sitting change; the
parent ticket's `Blocks [[feature-a-abi-oracle]]` note means the oracle work
cannot start until at least enough lanes are migrated that a type's identity
can be read from one place instead of per-backend `Syms[]` probing.

## Gate

`make test` + self-host byte-identical per lane; `make test-nilpy` too for any
lane NilPy code touches (2 and 3 especially, given the design note's NilPy
divergence evidence).
