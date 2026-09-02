---
slug: bug-c-block-scope-array-initialiser-past-256-elements
title: "A block-scope array initialiser past 256 elements is truncated or refused"
track: C
prio: 45
type: bug
status: done
created: 2026-09-02
found-by: frankD
summary: "ParseCLocalDeclAST still holds its initialiser element columns as 256-entry STACK arrays (arrElems/arrElemIdx). Past 256: the general expression arm raises `too many C array initializer elements' (loud, a refusal), and three other arms give up SILENTLY — two `nArrElems <= 255' guards in the string-ROW arm that stop copying mid-row and leave the tail zero, and two `nArrElems := -1' bails that drop the whole initialiser. The FILE-SCOPE sibling of exactly this was fixed on 2026-09-02 and was the last busybox blocker; this arm was left because it is RE-ENTRANT (the brace arm calls ParseCExpr, which can reach a statement-expression holding another declaration), so it needs a base-index stack rather than the flat pool the file-scope fix uses."
---

# Block scope is the arm the file-scope fix did not reach

`ParseCGlobalVarDecl`'s element columns became growable pools on 2026-09-02
(`CGIArrOffs..CGIArrTgt`), because busybox's generated `applet_main[]` crossed
256 entries and the silent bail sized it to one. `ParseCLocalDeclAST` has the
same columns, the same boundary, and four remaining guards:

| site | arm | behaviour past 256 |
| --- | --- | --- |
| `nArrElems > 255 then Error(...)` | element of a multi-dim brace list | refuses, loudly |
| two `nArrElems <= 255` | string literal standing for a char ROW | copies part of the row, leaves the tail zero, says nothing |
| two `nArrElems := -1` | the designated/flat list arms | drops the whole initialiser, says nothing |

**The loud arm is not the one an ordinary `int t[300] = {...}` takes.** Measured
against the pin: that declaration compiles without a diagnostic and the array
comes out uninitialised — the sum of its first 256 elements read back
`-1476027658` from stack garbage on one run. So the reachable behaviour is the
silent one in every shape tried, and the refusal is the arm hardest to reach.

## Why it was not fixed with its sibling

The file-scope pool is safe as flat shared state because `ParseCGlobalVarDecl`
is called only from the two top-level declaration loops and never re-enters
itself. `ParseCLocalDeclAST` does: the brace arm calls `ParseCExpr`, and a GNU
statement-expression inside an element can hold another declaration. A flat
pool would let the inner declaration overwrite the outer one's elements —
which is a worse bug than the cap.

So this needs a base index: `base := top` on entry to the initialiser parse,
elements at `pool[base + n]`, `top` restored at the end of that block. There is
one exit path out of the fill-then-store region and `Error` aborts the compile,
so the restore has one home; that is the thing to verify before writing it.

## The test to write

`test/c_global_array_init_over_256.c` is the file-scope shape and asserts the
THRESHOLD (256 and 257 read from one table), not the crash. The block-scope
version wants the same discipline plus a row that crosses the boundary
mid-string, because that arm truncates rather than bails and a whole-array
check would not see it.

## Log
- 2026-09-02 — resolved; this names the commit that carried the resolve, which is not always the one that carried the change — commit PENDING-COMMIT.
