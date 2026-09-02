---
slug: bug-a-generic-astleft-astright-walkers-recurse-into-kinds-that-overload-those-fields
track: A
prio: 55
type: bug
status: open
blocked-by: []
found: 2026-09-02
found-by: frankb-a9
owner:
summary: "ASTLeft/ASTRight are OVERLOADED PER NODE KIND -- for AN_ASM they hold an AsmBytes offset and length, not node references -- so any walker that recurses through them without consulting ASTKind indexes ASTKind with a byte offset. One instance is FIXED (ASTSubtreeHasLabel, where it returned a spurious True and suppressed a correct prune; repro and regression tests landed). CloneAST has the same shape by inspection and is UNVERIFIED for reachability; ~8 further generic walkers in ast_arena.inc / cparser.inc / ast_syminfer.inc were never audited. This ticket is the sweep."
---

# Generic ASTLeft/ASTRight walkers vs kinds that overload those fields

## The mechanism

`ASTLeft`/`ASTRight` are a two-slot payload whose MEANING depends on
`ASTKind`. For most kinds they are child node indices. For `AN_ASM` they are
not: `ParseAsmStatementAST` (pasparser_stmt.inc) and `CAsmBuildBlock`
(cparser.inc:7371) store an **AsmBytes offset** in `ASTLeft` and a **length**
in `ASTRight`, and ir.inc's `AN_ASM` arm reads them straight back out as
`IRAppend(IR_ASM, ASTLeft[node], ASTRight[node], ...)`.

A walker that recurses unconditionally therefore indexes `ASTKind` with a byte
offset. AsmBytes offsets run to 65535 while a body's node count can be far
smaller, so the failure mode is an **out-of-range read**, not a wrong answer.

## What is already done — do not redo this part

`ASTSubtreeHasLabel` is FIXED (early `Exit` for `AN_ASM` before the recursion,
which is also the correct answer on the merits: an asm block has no AST
children and is not an entry point). It was **not** merely latent there:
reached through `ASTSeqTailUnreachable`, the garbage read returned a spurious
`True` and SUPPRESSED a correct prune, so `Exit; asm nop end; WriteLn(Undef)`
emitted the undefined call and the binary would not start. Both frontends.
Regression tests `test/test_asm_in_unreachable_tail.pas` and
`test/c_asm_in_unreachable_tail.c`, both measured failing on the pre-fix
compiler.

## The sweep this ticket is for

`CloneAST` (ast_arena.inc) has the identical shape — it ends with
`ASTLeft[Result] := CloneAST(ASTLeft[node]); ASTRight[Result] := CloneAST(...)`
with no kind check — and would clone an `AN_ASM` by treating its offset and
length as nodes, producing a **corrupted asm block** rather than a
conservative over-keep. Whether any caller clones a subtree containing
`AN_ASM` is UNVERIFIED; establishing that is the first step, not the fix.

Others named by a one-line grep and never audited: `DynTargetIsRereadable`,
`NodeDynBaseRec`, `NodeDynBaseSym`, `NodeDynBaseTk`, `NodeDynDepth`
(ast_arena.inc), `InferSymTypeFromNode` (ast_syminfer.inc), `CExprLongRank`,
`CNodeArrayShape` (cparser.inc).

## The question worth answering before patching each one

Nine `if ASTKind[node] = AN_ASM then Exit` lines is the symptom, not the fix --
it is the same "enumerate the spellings" failure that this guard has now hit
twice for entry points. Ask instead whether the arena should expose
`ASTChildLeft(node)` / `ASTChildRight(node)` returning -1 for kinds whose slots
are payload, so a generic walker CANNOT get this wrong and a new overloaded
kind is handled once. `normalise-dont-special-case` argues for that shape; the
counter-argument is that the accessor hides a cost in the hottest walkers, and
that is worth measuring rather than assuming.

Also open: whether any kind besides `AN_ASM` overloads these two slots. The
grep behind this ticket found only `AN_ASM` assigning a non-node into them in
the Pascal and C parsers, but the other frontends (N/R/Z) were not searched.
