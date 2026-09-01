---
type: bug
track: A
prio: 6
summary: an exception handler arm's managed temp was finalized after the merge, so a try whose handler never runs paid a heap-lock round trip per call — 6.5x on a hot try
owner: frankB
---

## What

A `try`/`except` is ONE statement, so a by-value managed-record or interface temp
built inside a handler had its finalize emitted **after the merge** and ran on the
NORMAL path — the path where nothing was raised and the handler never executed.

Fourth statement kind to need the `IRFlushPostCallIntf` boundary, after `AN_IF`'s
arms (`bug-a-managed-temps-for-an-untaken-branch-are-still-init-and-finalized`),
the three loop bodies and `AN_CASE`'s arms (both closed today, `1308ef1f8` and
`a289b5529`).

## Measured — the control is the other spelling again

5M calls of a `try` whose handler never runs:

| | time |
| --- | --- |
| `on E: Exception do TakeR(MkR(k))`, pre-fix | 0.52 0.54 0.51 s |
| same, fixed | 0.08 0.07 0.08 s |
| `on E: Exception do if k >= 0 then TakeR(MkR(k))`, **pre-fix** | 0.07 0.08 0.07 s |

`sink=5000000` on all three. The `if`-wrapped spelling was already fast before
the fix, because `AN_IF` supplies the flush and changes nothing else — so the
handler paid ~6.5x for work the wrapped spelling never emitted, and the fix lands
on the wrapped timing rather than past it.

## Tests, and why one row is absent

`test/test_except_arm_temp_finalize.pas` covers the two leave paths an `if` arm
does not have — a bare `raise;` re-raise and an exception escaping the handler —
with the temp built BEFORE the leave, plus a handled arm and a never-raised arm.
Output matches FPC; clean under `-dPXX_HEAP_DEBUG`.

**No `assert_no_leak` row on it, deliberately.** Per arm, 500 trips:
`Handled` 2666/2664 live=2, `NotRaised` 1/0 live=1, `ReRaised` 2666/2664 live=2,
`Escaped` 3799/2820 **live=979**. The Escaped arm is
`bug-a-an-exception-that-escapes-its-handler-or-is-bare-re-raised-still-leaks-its-object`,
open and blocked on a Track U decision — a bound there would measure that ticket.
The Makefile says so where the row would go, and says to add it when that closes.

The discriminating guard is `test/test_except_arm_finalize_shape.pas` plus its
Makefile assertion over `PXXDBG=a.ir:Hot`: **AFTER-MERGE** on the pre-fix binary,
**IN-ARM** on the fixed one, and **NO-FINALIZE-EMITTED** treated as a failure of
aim rather than a pass.

`try` BODY and `finally` block were checked at the same time and were already
IN-ARM; only the handler arms were missing the flush.

## Log

- 2026-09-01 — found by asking which statement kinds were still uncovered after
  the loop and `case` fixes; fixed and closed in the same session.
  Fixed in commit dcadde29f.
  (Citation kept on ONE line on purpose: a `commit <sha>` wrapped onto a
  continuation line is invisible to both `progress.py check` and `sync.sh` fill
  — bug-t-a-wrapped-resolve-citation-is-invisible-to-both-check-and-fill. I hand
  wrote this Log entry and wrapped it, and the placeholder sat unfilled through a
  push exactly as that ticket describes.)
