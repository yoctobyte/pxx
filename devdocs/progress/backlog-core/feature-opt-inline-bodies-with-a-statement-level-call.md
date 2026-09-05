---
track: A
prio: 35
type: feature
status: backlog
owner: unassigned
blocked-by: []
found: 2026-09-05
found-by: frank-optimize, measuring reach for feature-inline-nonleaf-and-branch-locals
summary: "67 distinct functions across 13 example programs plus compiler.pas are rejected by the inline statement validator solely because their body contains a bare procedure-call statement -- the second-largest blocker measured, ahead of `for` (32) and `case` (19), and behind only `while` (102). No ticket names this shape. The non-leaf machinery already handles calls in EXPRESSION position (InlineBodyHasCall forces argument temp-capture); this is the same calls in STATEMENT position, which the AN_SEQ walker rejects outright."
---

# Inline bodies containing a statement-level procedure call

- **Type:** feature (optimizer — **Track O**, file-owned by **Track A**).
- Found 2026-09-05 while measuring reach for
  [[feature-inline-nonleaf-and-branch-locals]], with `PXXDBG=a.inlinedecline`.

## Measured

`TryRetainInlineStmtBody`'s `AN_SEQ` walker accepts exactly `AN_ASSIGN` and
`AN_IF` and rejects everything else. Counting the rejecting kind for bodies that
had already cleared the locals and Result gates, across 13 example programs plus
`compiler.pas`, deduplicated by function name:

| blocking statement | distinct functions |
| --- | --- |
| `while` | 102 |
| **bare call statement (`AN_CALL`)** | **67** |
| `for` | 32 |
| `case` | 19 |

So a body shaped like

```pascal
function F(x: Integer): Integer;
begin
  DoSomething(x);      { <- rejected here }
  Result := x * 2;
end;
```

never retains, at any -O level.

## Why it is plausibly cheaper than the loop slices

The hard part of the loop slices is **definite assignment through a construct
that may execute zero times** — `for i := 1 to n do Result := ...` does not
assign Result when n < 1. A statement-level call has no such problem: it is
straight-line, it always executes, and definite-assignment state passes through
it unchanged.

The machinery for calls already exists and is fuzz-proven. Non-leaf slice 1
accepts calls in EXPRESSION position and sets `InlineBodyHasCall`, which forces
the splice to temp-capture every argument so a direct-substituted pure argument
cannot be reordered across the inner call's side effects. **A statement-level
call needs the same guarantee and no new analysis** — the work is admitting the
node kind in the walker and confirming the existing capture rule covers it.

## The hazard

**Side-effect ORDER, and it will not fail a value assertion.** A statement call's
effects must land between the effects of the statements around it. The existing
`test_inline_nonleaf.pas` pattern is the right control — a global counter
asserted exactly — because a value check cannot see an effect that moved, only
one that changed a number.

`FrameIntrinsicUsed` already disables non-leaf inlining wholesale when a unit
walks the saved-fp chain; a statement-level call is a call and inherits that.

## What must be measured before it lands

**Reach, then delivery, in that order** — the mistake
[[feature-inline-nonleaf-and-branch-locals]] made by picking on the bound. 67 is
an upper bound: these bodies cleared the earlier gates and hit this kind, but
admitting the kind does not make them all inline. And a function whose body calls
something is doing more work per call than a pure leaf, so the value per site is
lower than the leaf case even where it fires.
