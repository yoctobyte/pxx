---
summary: "C: a multi-dim array subscript that is itself a multi-dim array read (g3[g9[i][j][k]][..]) miscompiles — TWO bugs: parse-time NDInfo* clobber + codegen nested-index clobber"
type: bug
prio: 55
---

# C: multi-dim array indexed by another multi-dim array read miscompiles

- **Type:** bug (Track A — C frontend flatten + codegen). Silent wrong value on
  read; IR_UNSUPPORTED (kind-5 AN_BINOP) on some lvalues. Valid C.
- **Found:** 2026-07-18 csmith campaign (seeds 5004, 40020 = the compile-fails;
  and hand cases). Deeply investigated; NOT yet fixed (partial fix reverted).

## Minimal repros

```c
static int g3[2][3] = {{1,2,3},{4,5,6}};
static int g9[3][1][3] = {{{0,0,0}},{{0,0,0}},{{1,0,0}}};   /* g9[2][0][0]=1 */
int r = g3[1][g9[2][0][0]];          /* want g3[1][1]=5; pxx=0  (RVALUE read) */
g3[g9[0][0][0]][g9[2][0][0]] = 88;   /* want g3[0][1]=88; pxx writes wrong slot */
```

- gcc correct; pxx wrong. HOISTING the inner read to a temp fixes it
  (`int v=g9[2][0][0]; g3[1][v]` = 5 correct) — so the flatten AST *can* be right;
  the bug is (a) the flatten is corrupted at parse for the inline form, and
  (b) codegen mishandles a nested index even when the flatten is correct.

## TWO root causes (both needed for a full fix)

1. **Parse-time NDInfo* clobber.** The multi-dim flatten (`ParseCPostfixTail`,
   the `NodeArrNDInfo(node)` branch) uses the SHARED globals NDInfoNDims/NDInfoLo/
   NDInfoSpan. Parsing a later subscript that is itself a multi-dim read re-calls
   `NodeArrNDInfo` (for the inner array) and CLOBBERS those globals, so the outer
   array's `while (nIdx < NDInfoNDims)` bound and `BuildFlatNDIndex` spans are the
   INNER array's -> wrong flatten (wrong full-vs-partial decision + wrong strides).
   DRAFT FIX (reverted): re-call `NodeArrNDInfo(node)` after each subscript's
   ParseCExpr to restore the globals. This made 5004/40020 compile AND match gcc,
   but a hand lvalue test still failed -> bug #2 remains, so the draft was
   reverted (a partial fix that masks a residual silent miscompile is worse than
   a loud compile-fail).

2. **Codegen nested-index clobber.** Even with a correct flatten AST,
   `AN_INDEX(g3_multidim, index-expr-containing-a-nested-AN_INDEX)` reads the wrong
   element on the RVALUE path (IRLowerAST). A 1-D array with the same nested-index
   expression (`a[3 + g9[2][0][0]]`) is CORRECT, and hoisting the inner read to a
   temp is CORRECT — so it is specific to the multi-dim IR_INDEX codegen: the
   nested IR_INDEX in the index subtree clobbers a register the outer index/base
   computation needs. The lvalue path (IRLowerAddress) handles some cases but not
   all.

## Fix plan

Do BOTH: (1) snapshot/restore NDInfo* across subscript parsing (the reverted
draft, made robust), AND (2) fix the multi-dim IR_INDEX codegen to save/restore
the base (or evaluate the index into a temp) when the index subtree contains a
nested IR_INDEX. Verify with a hand rvalue+lvalue matrix AND re-run csmith.

## Acceptance

- The repros match gcc (read=5, write lands at g3[0][1]); csmith seeds 5004/40020
  match gcc; C-conformance 220/220 + self-host byte-identical; test/*.c regression.
