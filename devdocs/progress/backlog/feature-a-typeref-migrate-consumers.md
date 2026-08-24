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

## 2026-08-24 — the 2026-08-19 triage is out of date, and lane 4 has a measured prerequisite

**Correction first.** The triage above says *"`TTypeRef` appears 4 times in
`compiler/defs.inc` … and **zero** times in `compiler/symtab.inc` and
`compiler/ir.inc`. So lane 1 has not started."* Measured today:

```
compiler/symtab.inc : 59 mentions      compiler/ir.inc : 19
SymSyncTypeRef call sites : 105  (pyparser 54, pasparser_stmt 17, cparser 8,
                                  ir 8, symtab 7, pasparser_decl 5, ...)
SymTR read sites already migrated : ir.inc, ir_codegen386.inc, ir_codegen_xtensa.inc
```

Lane 1 is substantially landed — write-side sync **and** a first set of reads.
The triage counted a stale checkout or grepped the type name rather than the
array name; either way, do not plan off it.

### Lane 4 (proc return types) is now WANTED by a filed bug

[[bug-p-dereferencing-a-function-result-of-pointer-to-pchar-loses-the-shape]]:
`GetQ^` where `GetQ: ^PChar` is wrong in the four contexts that refuse to guess,
because a proc records `ProcRetPtrElemTk`/`Rec` — the immediate pointee — and
nothing about the return pointer's DEPTH or ultimate BASE, so `PChar` and
`^PChar` are indistinguishable as return types. The lane is small: **10 write
sites, 7 read sites.**

### Two things block it, both measured today, both in this ticket's own subject

**1. `TTypeRef` cannot express a pointer's depth.** As declared
(`defs.inc:1559`) it has `PtrBaseTk`/`PtrBaseRec` and `DynDepth` — *dynamic
array* nesting — and no pointer-level count. Symbols carry theirs OUTSIDE
`SymTR`, in `SymPtrDepth`. So a `TTypeRef` today is strictly less expressive
than the parallel arrays it is meant to replace, for exactly the case that
motivates the migration.

**2. And the field is fed the wrong half.** `SymSyncTypeRef` does

```pascal
  SymTR[idx].PtrBaseTk  := Ord(Syms[idx].PtrElemTk);   { the IMMEDIATE pointee }
```

into a field whose name and comment say *base*. Measured with
`PXXDBG=a.symptr`:

| declaration | depth | `PtrElemTk` (immediate) | `SymPtrBaseTk` (ultimate) |
| --- | --- | --- | --- |
| `pc: PChar` | 1 | tyChar | tyChar |
| `ppc: ^PChar` | 2 | **tyPointer** | **tyChar** |
| `pr: ^TRec` | 1 | tyRecord | tyRecord (rec 29) |
| `raw: Pointer` | 0 | tyUnknown | tyUnknown |

They coincide at depth ≤ 1, which is why the single existing reader
(`ir.inc:2506`, the char-pointer check) is correct today and why nothing has
caught it.

### The obvious fix is NOT safe yet — this is the part worth recording

The clean shape is: `TTypeRef` gains `PtrDepth`, and `PtrBaseTk`/`PtrBaseRec`
are fed from `SymPtrBaseTk`/`SymPtrBaseRec` so they mean what they are named
(the immediate pointee stays derivable: depth > 1 ⇒ tyPointer, else the base —
which is exactly how the deref chain in `pasparser_lval.inc` already reasons).
The one existing reader then guards on `PtrDepth = 1`, which is a correctness
improvement in its own right.

**It cannot land until the old arrays are themselves in lockstep, and they are
not:**

```
Syms[..].PtrElemTk := ...  outside symtab.inc : 21 sites
  ast_syminfer 6 · cparser 9 · pasparser_decl 2 · pasparser_proc 1
  · pasparser_stmt 1 · pyparser 2
SymPtrDepth[..] := ...     outside symtab.inc :  9 sites  (all cparser)
```

So **twelve post-creation sites set the immediate pointee and never touch depth
or base.** Feeding `PtrBaseTk` from `SymPtrBaseTk` today would make it read
`tyUnknown` at every symbol those twelve touch, and the char-pointer check would
silently stop firing. That is the same shape as the two backend migrations
reverted on 2026-08-01 (`9b73ff4d6`, `e484fde67`) — a parallel-array sync miss
that a happy-path corpus does not exercise — and the same lesson: *sync the
write side first, then migrate reads.*

### Concrete next step for whoever takes this

1. Make the pointer triple (`PtrElemTk`/`PtrElemRec`, `SymPtrDepth`,
   `SymPtrBaseTk`/`SymPtrBaseRec`) written together at all 21 post-creation
   sites — a `SetSymPointerType(idx, elemTk, elemRec, depth, baseTk, baseRec)`
   helper, so there is one place to forget instead of five fields. That is
   independently valuable and is the actual root cause behind the filed bug.
2. Then add `PtrDepth` to `TTypeRef` and re-point `PtrBaseTk`/`Rec` at the
   ultimate base, updating `ir.inc:2506` to guard on depth.
3. Then lane 4 proper: `ProcRetTR`, populated at the 10 sites, read by a new
   `AN_CALL` arm in the deref chain — which is what closes the filed bug.

Each step under `make compiler/pascal26` + `tools/gate.sh quick`, and re-run the
88-pair PChar differential recorded in
[[refactor-centralize-managed-string-pchar-conversion]] (currently 5 diverging,
all of them the `GetQ^` shape) as the acceptance check.

**Also: this ticket is in `backlog/`, which the 2026-08-19 triage asked for.
That move happened. No action needed.**

## 2026-08-24, step 1's first instalment — `SetSymPointerType`, and the inference site

The step-1 plan recorded above (*"make the pointer triple written together at
all 21 post-creation sites — a `SetSymPointerType` helper, so there is one place
to forget instead of five fields"*) now has its helper and its first converted
call site.

### The helpers

- **`SetSymPointerType(idx, elemTk, elemRec, depth, baseTk, baseRec)`** —
  THE one place a symbol's pointer identity is written after its `Alloc*`. All
  five fields, then `SymSyncTypeRef`, so `SymTR` cannot go stale behind it.
- **`SetSymPointerTo(idx, elemTk, elemRec)`** — the single-level case, for a
  caller whose source records only the pointee. `^T` where T is not itself a
  pointer **is** depth 1 over base T; the two are the same fact, so deriving
  them is not a guess. When T *is* a pointer the depth is genuinely unknown and
  this declines, leaving depth 0 rather than inventing a 1 that would make
  `^PChar` claim to be a `PChar`.

The `depth = 0` escape is deliberate and is the honest half of the design: a
caller that does not know is at least **visibly declining** instead of silently
forgetting, which is the whole failure mode.

### Converted: `InferSymTypeFromNode` (`ast_syminfer.inc`)

Six branches, and they split exactly along whether the source records depth:

| inferred from | source | result |
| --- | --- | --- |
| another SYMBOL | `SymPtrDepth`/`SymPtrBaseTk`/`Rec` | **exact** |
| a pointer ALIAS | `AliasPtrDepth`/`AliasPtrBaseTk`/`Rec` | **exact** |
| `PChar(x)` | definition | **exact** (1 over tyChar) |
| `@x` | x's own type | derived, declines if x is a pointer |
| a record FIELD | `UFldPtrElemTk`/`Rec` only — no `UFldPtrDepth` | derived |
| a function RESULT | `ProcRetPtrElemTk`/`Rec` only — no depth | derived |

The last two are the shortfalls this ticket exists to remove; the function-result
one is filed as
[[bug-p-dereferencing-a-function-result-of-pointer-to-pchar-loses-the-shape]].

### What it fixed, and how it was proven not to break anything else

`var q := pp` where `pp: ^PChar` lost the char-ness one level in, because only
the pointee was copied:

```
before:  132814934638624      'x' + q^ -> 132814934638744     q^ = 'alpha' -> FALSE
after:   alpha                              xalpha                              TRUE
```

Proven neutral by an **A/B binary comparison**, which is the technique this
ticket's 2026-08-01 revert lacked: the compiler built *before* the change and
the compiler built *after* it were each used to compile the same sources, and
the resulting binaries diffed.

```
compiler.pas                         BINARY IDENTICAL
test_pchar_pointer_to_pchar.pas      BINARY IDENTICAL
test_pchar_array_of_pointer_to_pchar BINARY IDENTICAL
test_not_operand_type_matrix.pas     BINARY IDENTICAL
test_basic_comprehensive.bas         BINARY IDENTICAL
c_builtin_bits.c                     BINARY IDENTICAL
```

That is stronger than "the tests pass" — it is "no emitted byte moved, in any
frontend" — and it is the standard the remaining conversions should be held to.

### Test

`test/test_inferred_pointer_keeps_its_depth.pas`. FPC cannot compile it (inline
`var` in a statement block is a pxx/Delphi form, not objfpc), so the oracle is
the **explicitly typed twin printed beside each inferred row**: every line must
have two equal halves, and the explicit half is separately pinned against fpc
3.2.2 by `test_pchar_pointer_to_pchar.pas`. `test-core` asserts both the
recorded output *and* the halves-are-equal invariant on its own, because a pair
that drifted apart would still match a regenerated `.expected`. Verified to FAIL
on the pre-change compiler, on all three affected rows. Cross-checked on
i386 / aarch64 / arm32 / riscv32.

### Step 1 is DONE — every post-creation site now goes through the helper

`grep 'Syms\[.*\].PtrElemTk :='` outside `symtab.inc` returns **nothing**.
The 15 remaining sites landed in two A/B-verified batches after the
`ast_syminfer` one: `pasparser_decl` 2, `pasparser_proc` 1, `pasparser_stmt` 1,
`pyparser` 2, then `cparser` 9. Reference binary compiled the same sources
before and after each batch; `compiler.pas`, three PChar/`not`/depth Pascal
tests, `test_basic_comprehensive.bas`, three NilPy tests and eight C tests
(VLA, 2-D row length, decay stride, fn-pointer array, `**` return, called
result, ptr-array field) were **binary identical** every time. The compiler's
own code section shrank 1,306 bytes in the cparser batch alone — the helper
replaces five stores at nine sites.

**Two findings worth carrying forward:**

- **C's parameter table has the full triple, Pascal's does not.** `cparser`
  threads `pdepths[i]` / `pbasetk[i]` / `pbaserec[i]` alongside `pelemtk`, so a
  C `char **argv` parameter keeps its depth. `pasparser_proc`'s parallel
  `ptypesPtrElemTk` / `ptypesPtrElemRec` have **no depth sibling**, so that site
  had to take the derived single-level answer (`SetSymPointerTo`) and a Pascal
  `^PChar` PARAMETER still arrives at depth 1 instead of 2. That is the same
  class of loss as the inference bug just fixed, in the one place a helper call
  cannot paper over: the metadata genuinely is not recorded. Extending the
  param table is a prerequisite for step 2's `PtrDepth = 1` guard being safe for
  Pascal parameters — do it as the first half of step 2, not as an afterthought.
- **Do not edit sources while a gate runs.** `gate.sh quick` rebuilds from the
  working tree; a mid-run edit produced a *bogus* RED ("the fixedpoint reached
  from PINNED differs from compiler/pascal26") that was pure contamination. The
  re-run on a quiet tree was GREEN with no change to the sources.

### Still open, in order

1. ~~The other 20 post-creation sites.~~ **DONE** (see above).
2. Then `TTypeRef` gains `PtrDepth` and `PtrBaseTk`/`Rec` are re-pointed at the
   ultimate base, with `ir.inc:2506` guarding on `PtrDepth = 1`.
3. Then lane 4 (`ProcRetTR`), which closes the filed `GetQ^` bug.
