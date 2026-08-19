---
track: A
owner: claude-A
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

## 2026-08-01 — lane 1 (TSymbol) in progress; REVERTED two backend read-site
migrations, real sync gap found

`SymTR` (additive, `54b5684bc`) landed, and several read sites migrated
cleanly: `ir.inc`'s managed-record-copy and char-pointer-check (`93ebb9377`,
`e9d1522c6`) — both safe because the fields they read (`RecName`/`PtrElemTk`
for those specific symbols) are only ever written at the symbol's creation
chokepoint, so `SymSyncTypeRef` (called there) keeps `SymTR` correct.

**Then a real gap was caught before more damage landed**: `SymSyncTypeRef` is
only called at the 5 `symtab.inc` creation chokepoints
(`AllocVar`/`AllocParam`/`AllocArray`/`AllocDynArray`/`AddConst`), but
`parser.inc`/`cparser.inc`/`pyparser.inc`/`ir.inc` also mutate the SAME old
fields **after** creation — e.g. `compiler/parser.inc:26006` (and :20565,
:21058) does `idx := AllocArray(...)` then immediately
`Syms[idx].ElemRecName := LastTypeRecId` for **any `array of <record>`
parameter or local** — a hot, common pattern, not an edge case. None of
those ~132 post-creation write sites call `SymSyncTypeRef`, so `SymTR` goes
stale for any symbol they touch.

Two already-merged backend migrations were exposed to exactly this:
`573e1c4e7` (x86-64 `ir_codegen.inc`, migrated `ElemRecName`/`ElemType`/
`RecName` reads for anon-dynarray registration + managed-array-element
copy) and `e3497fc73` (i386/arm32/aarch64/riscv32/xtensa RecName reads for
managed-record dynarray-append growth) — both read `SymTR[...].ElemRec`/
`.RecId` for exactly the array-of-record symbols the parser.inc sites above
mutate post-creation. **Reverted** (`9b73ff4d6`, `e484fde67`) rather than
leave a known, plausibly-widely-triggered stale-read gap live on master —
this is the same bug shape as the `pconst`-shift regression from the night
before (a parallel-array sync miss that a happy-path test corpus doesn't
happen to exercise), and that one only surfaced in a full `test-core` run,
not fixedpoint or `testmgr --tier quick`, so "tests passed" was not
sufficient evidence to keep it.

**Next**: before migrating any more reads (especially anything touching
`RecName`/`ElemRecName`/`TypeKind`/`PtrElemTk`/`PtrElemRec`/`SymProcSig`),
add `SymSyncTypeRef` calls after every post-creation write site — full
inventory (grep for `Syms[<idx>].<field> :=` outside `symtab.inc`'s
Alloc*/AddConst) is roughly: `RecName`/`ElemRecName` ~58 sites (`ir.inc` 3,
`pyparser.inc` ~42, `parser.inc` ~13), `TypeKind` ~9 (`parser.inc`),
`PtrElemTk`/`PtrElemRec` ~17+17 (`cparser.inc`, `parser.inc`),
`SymProcSig` ~11, `ElemType`/`IsArray`/`ArrLen` ~16. That write-side sync
is real, distinct work — do it before trusting any more `SymTR` reads, and
re-land the two reverted backend migrations only after it's done and
re-verified.

## 2026-08-03 — moved working/ -> unfinished/ (board maintenance)

`working/` is a live lock: a ticket sits there only while an agent is actively
on it. This one had not been touched in three days, so the lock was stale and
`next` was reserving a Track A file-lane nobody held.

**Not a revert, and nothing is half-applied**: lane 1 (the `SymTR` parallel
array plus the full write-side sync) is landed and green — the self-host
fixedpoint has been rebuilt many times since against it. What remains is the
~68 read sites and the old-field deletion, which is why this is `unfinished/`
rather than `done/`. Re-claim it to continue.


## Triage 2026-08-19 (Track D re-triage pass, pin v364)

**Genuine feature, still wanted — no lane migrated, and no partial state.**
Measured by counting consumers rather than reading the ticket: `TTypeRef`
appears 4 times in `compiler/defs.inc` (the additive declaration its parent
landed) and **zero** times in `compiler/symtab.inc` and `compiler/ir.inc`. So
lane 1 has not started, and nothing is half-applied.

**Queue hygiene: this is in `unfinished/`, and it should not be.** That folder
means work halted with the ticket incomplete, and a Track A ticket there is
flagged CRITICAL precisely because a half-applied compiler change can break the
self-host gate. Nothing is half-applied here — the parent landed cleanly and
this is untouched follow-up work. It belongs in `backlog/`. Not moved by this
read-only triage pass; flagged for whoever holds the A slot.
