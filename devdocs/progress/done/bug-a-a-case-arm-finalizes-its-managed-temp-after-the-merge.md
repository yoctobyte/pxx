---
type: bug
track: A
prio: 6
summary: a case arm's managed temp was finalized after the merge, so every arm paid a heap-lock round trip — 7.3x on a hot dispatch, and the if spelling was already fast
owner: frankB
---

## What

`AN_IF` flushes `IRFlushPostCallIntf` per arm. `AN_CASE` did not. A `case` is ONE
statement, so a by-value managed-record or interface temp built in one arm had
its finalize emitted **after the merge label** and ran on every path through the
statement — including the arms that build nothing.

Cost, not corruption: the temp is nil-inited, so the stray finalize is a
heap-lock round trip that releases nothing. The cost is not small.

## Measured — and the control is the other spelling

20M calls of `Hot(0)`, the arm that allocates never taken. Interleaved, min of
five, same machine, same source:

| | time |
| --- | --- |
| `case`, pre-fix binary | 1.75 1.76 1.77 1.78 1.78 s |
| `case`, fixed binary | 0.24 0.24 0.24 0.24 0.25 s |
| `if`/`else if`, **pre-fix** binary | 0.23 0.23 0.24 s |

`sink=20000000` on all three and on FPC. So `case` paid **7.3x** for a finalize
the `if` spelling never emitted, and the fix lands it exactly on the `if` timing
rather than somewhere better — which is the reading that says the stray work was
removed and nothing was added.

Same defect as `bug-a-managed-temps-for-an-untaken-branch-are-still-init-and-
finalized`, which fixed `if` arms and whose comment measured the same mechanism
at 20M calls. `case` was never covered — the sibling of a double case.

## Two test rows, aimed at different failures

`test/test_case_arm_temp_finalize.pas` reads **identically** on the pre-fix
binary (2369/2364 live=5, `sink=502445`), and must: a stray finalize on a
nil-inited temp releases nothing. So it does not guard the fix. It guards the
opposite direction — a finalize moved into the WRONG arm, which is a double free
— which is why every arm is taken many times and it runs under
`-dPXX_HEAP_DEBUG`.

`test/test_case_arm_finalize_shape.pas` plus its Makefile assertion is the row
that discriminates: it reads `PXXDBG=a.ir:Hot` and asks whether the last
`copy_rec_managed` precedes or follows the last `label`.

- pre-fix binary → **AFTER-MERGE** (fails)
- fixed binary → **IN-ARM** (passes)
- a `case` with no managed temp → **NO-FINALIZE-EMITTED**, which the harness
  treats as a failure of AIM rather than a pass, because a comparison whose
  subject never ran cannot fail either.

## Log

- 2026-09-01 — found by grepping for the sibling of the loop-flush fix
  (`1308ef1f8`) rather than waiting for a report; fixed and closed in the same
  session, commit PENDING-COMMIT.
