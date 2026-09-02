---
slug: bug-a-generic-astleft-astright-walkers-recurse-into-kinds-that-overload-those-fields
track: A
prio: 55
type: bug
status: done
blocked-by: []
found: 2026-09-02
found-by: frankb-a9
owner: frankb-a9
summary: "RESOLVED. ASTLeft/ASTRight are OVERLOADED PER NODE KIND, and the overload set is EIGHT kinds, not one: AN_ASM (AsmBytes offset + length), AN_PTR_CAST (proc-sig index), AN_VIRTUAL_CALL / AN_CLASS_VIRTUAL_CALL (VMT slot), AN_CALL (ProcRetRecId), AN_METHODREF (VMT slot), AN_TYPEINFO and AN_CLASSREF (0/1 flags). Three of those are VALID node indices, so no out-of-range read will ever catch them. Nine walkers recurse through the slots generically; the other 32 self-recursive walkers are kind-dispatched and are NOT vulnerable. FIXED by a single table in ast_arena.inc (ASTLeftIsChild / ASTRightIsChild + ASTChildLeft / ASTChildRight) that all nine now ask, plus tools/ast_slot_overloads.py, which fails if a kind drifts out of it. Measured cost: within noise of the self-host compile. NO OBSERVABLE INSTANCE was found in test/ (2233 files, two probes, 238k firings) -- this lands as a guard with an explicitly negative reachability result, not as a repro. Full tier at dcb6f2c17: 3804 ok, 6 SKIP, 1 FAIL, and that FAIL is a Track T ratchet that has been red since its own arming commit (bug-t-the-exit-observable-ratchet-was-red-at-its-own-arming-commit), not this change."
---

# Generic ASTLeft/ASTRight walkers vs kinds that overload those fields

## The mechanism

`ASTLeft`/`ASTRight` are a two-slot payload whose MEANING depends on
`ASTKind`. For most kinds they are child node indices. For eight they are not,
and a walker that recurses without asking indexes `ASTKind` with a byte offset,
a VMT slot, a record id or a flag.

## The overload set, measured

Every `x := AllocNode(AN_K)` (and every `ASTKind[x] := AN_K` re-kinding) paired
with the writes to `ASTLeft[x]` / `ASTRight[x]` that follow it, attribution
stopping at the next node construction:

| kind | slot | what is actually in it |
| --- | --- | --- |
| `AN_ASM` | Left, Right | AsmBytes offset, block length |
| `AN_PTR_CAST` | Right | proc-signature index (read by `CNodeProcSig`) |
| `AN_VIRTUAL_CALL` | Right | VMT slot |
| `AN_CLASS_VIRTUAL_CALL` | Right | built as an `AN_CALL`, re-kinded, inherits its |
| `AN_CALL` | Right | `ProcRetRecId` — every write site, all 12 |
| `AN_METHODREF` | Right | VMT slot, so `@baseref.VirtualMethod` captures the override |
| `AN_TYPEINFO` | Left | `1` = registered through `RegisterTypeInfoReq` |
| `AN_CLASSREF` | Right | `1` = the VT_CLASSREF variant lowering, `0` = raw pointer |

**Three failure shapes, and only the first is loud.** `AN_ASM`'s offsets run
past the node count, so the read goes out of range. `AN_PTR_CAST`'s signature
index is in range and one value hit node 0, whose own Left is 0 — a recursion
fixed point that segfaulted the compiler with no diagnostic on busybox's ash.
**A VMT slot, a record id and a 0/1 flag are all VALID node indices**: nothing
goes out of range, nothing loops, nothing errors, and the walker gets a
well-formed answer about an unrelated subtree.

`AN_METHODREF` was found by the census tool, not by reading. That is the
argument for the tool in one line.

## Which walkers, and which are NOT

41 functions call themselves on `ASTLeft[..]`/`ASTRight[..]`. **Nine** recurse
outside any kind arm:

| | |
| --- | --- |
| `CloneAST` | ast_arena.inc |
| `CASTNodeOccursIn` | cir.inc — never mentions `ASTKind` at all |
| `IRLowerCSwitchDispatchScan` | cir.inc — had a hand-written `AN_PTR_CAST` arm |
| `CloneToInlineRegion` | inline_expand.inc |
| `InlineStmtRhsLocalsWritten` | inline_expand.inc |
| `IRCloneInlineBody` | ir.inc |
| `SLHasYield`, `SLRewriteLoopJumps` | pasparser_stmt.inc |
| `AstDumpTree` | ir_codegen.inc |

The other 32 — `ResolveNodeRec`, `IRLowerAST`, `IsNodePChar`, `IRPointerStride`,
`CNodePtrDepth`, `ASTConstIntValue` and the rest — recurse only inside a
specific kind arm and **cannot be handed a payload slot at all.** That includes
six of the eight this ticket originally listed as unaudited
(`DynTargetIsRereadable`, `NodeDynDepth`, `NodeDynBaseTk/Rec/Sym`,
`CExprLongRank`, `CNodeArrayShape`): not vulnerable, struck rather than left
looking like open work.

## The fix

One table in `ast_arena.inc`, asked by all nine.

**Two forms, because three of the nine are CLONERS.** `ASTChildLeft` /
`ASTChildRight` answer `-1` for a payload slot, which is what a reader wants.
A cloner must copy the payload **verbatim**: `CloneAST` used to do
`ASTRight[clone] := CloneAST(recId)`, cloning node #recId and storing the
CLONE's index as the record id, and `-1` would only trade a corrupt id for a
missing one. So the table is a predicate — `ASTLeftIsChild` / `ASTRightIsChild`
— with the accessor built on top.

`defs.inc`'s `AN_PTR_CAST` comment used to say "if you add another overload,
say so HERE" while listing only itself; it now points at the table.

## The cost, since the objection was raised before the fix

The counter-argument was that an accessor hides a cost in the hottest walkers.
It does not reach them: the 32 kind-dispatched walkers, which include every hot
one, are untouched. Measured anyway — the two binaries compiling
`compiler/compiler.pas`, interleaved, min of N, same box: see the logbook entry
for the numbers. No separation worth a design change.

## What was NOT found, stated as a result

`tools/ast_slot_overloads.py --self-check` is a guard with a positive control,
and the two probe sweeps below are aimed instruments — but **no observable
defect was reproduced.**

- **`IRLowerCSwitchDispatchScan` × `AN_ASM`.** A probe in the scan shows it
  really does recurse into the payload (`AN_ASM node=8786 left=63 right=1
  nodecount=8918`). 306 generated shapes — varying asm byte-length, case count,
  switch count, and decorrelating the byte offset from the node index — diffed
  against gcc, with the compile branched on before comparing: **0 differ, 0
  compile failures.** A second probe counting reachable `AN_CASE`/`AN_DEFAULT`
  markers under the garbage subtree answered **0 on every one of 120 shapes**,
  which is why: the walk lands on ordinary expression nodes.
- **`CloneAST`, whole corpus.** All 2233 files in `test/`: 86 clones of a
  payload-carrying kind, every one `AN_PTR_CAST` with `Right = -1`.
- **The two body cloners at `-O3`, whole corpus.** 238,539 clones of a
  payload-carrying kind, every one `AN_CALL` with `Right = -1`. C and Pascal
  leave that slot -1; the frontend that fills it is NilPy, and no NilPy body
  carrying one reached a cloner.

So the corpus does not reach the corrupting case **today**. That is a
reachability accident — `AN_CALL` is cloned in bulk and one frontend does park
a record id there — not a property to rely on.

## Regression tests

- `test/c_asm_in_switch.c` (default and `-O3`) — asm in switch arms, including
  an arm that is nothing but asm, a nested switch, and a multi-instruction
  template so the offset is large. Pins that every arm still dispatches.
- `test/c_asm_in_inline_body.c` (default and `-O3`) — asm inside a body the
  inliner clones, nested one deep. `-O3` matters: the inliner does not fire
  below it, so a default-only test measures the wrong population.
- `test/ast_slot_writes.expected` + `tools/ast_slot_overloads.py --self-check`
  — the census snapshot and its positive control.
- `test/test_asm_in_unreachable_tail.pas` / `c_asm_in_unreachable_tail.c`
  (pre-existing, from the `ASTSubtreeHasLabel` fix) still pass through the
  table rather than through a hand-written `AN_ASM` arm.

## Still open

**Whether the frontends this compiler has beyond P/C/N/R/Z overload a slot.**
The census reads `compiler/*.inc` wholesale, so `aparser` `bparser` `eparser`
`fparser` `gparser` `lparser` `wparser` are all in it — but only for the
`AllocNode`-adjacent write shape. A slot written through a helper, far from the
construction, is invisible to it. The snapshot makes such a write show up as a
diff the next time anything near it changes; it does not find one today.

**`AN_INTF_CALL` and `AN_CALL_IND` are deliberately NOT in the table.** Both
have a real node in `Right` (the interface value; the callee expression) and
park their slot number in `ASTSOffset` / `ASTIVal` instead. That is the shape
the other six should have had.

## The tier, since the load-bearing claim spans eight frontends

`--tier full` at `dcb6f2c17`, from a tree verified equal to `origin/master`,
binary `c7c83465b0e9`: **3804 ok, 6 SKIP, 1 FAIL.**

The quick tier covers two frontends and the claim "AN_CALL's ASTRight is never
a child" covers eight, which is why a full run was worth the ten minutes.

The four new rows are proven to have RUN, not just to have not failed —
`test-core#945..948` carry the four `ok:` compile lines and the census tool's
self-check line. A tier row that passes because nothing executed is the failure
this repo has a whole rule about.

**The single FAIL is not this change.** `tools-devtest#00` fails on
`exit_observable_devtest.py`'s stdout-only share ratchet. Removing this
commit's four Makefile rows leaves the measurement byte-identical at
667 of 718 — they are x86-64 `$(COMPILER)` rows and that population is
`run_target.sh` cross-target rows. Running the guard unchanged against
successive Makefiles shows it was RED at its own arming commit, by three rows,
before anything drifted. Filed as
[[bug-t-the-exit-observable-ratchet-was-red-at-its-own-arming-commit]].

A FIRST RUN OF THIS TIER WAS DISCARDED, not read: `tools/sync.sh` rebased in 25
commits mid-run, three touching `compiler/`, so the binary was snapshotted at
one sha while the harness read sources from a tree that had moved. Killed,
rebuilt (`c7c83465b0e9`), targeted set re-run green, tier restarted from a
clean tree. The trigger is worth naming because it is not an edit you make: it
is a pull you invite, and "my tree is final" is exactly the state in which you
stop counting sync as touching the instrument.
