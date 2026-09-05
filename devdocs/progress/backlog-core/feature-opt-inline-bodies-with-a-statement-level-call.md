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

## 2026-09-05 — IMPLEMENTED AND MEASURED: it delivers nothing on real programs

Implemented (`InlineStmtCallOk`, -O3, rejecting any callee with an explicitly
by-ref parameter because a `var` argument lets the callee write a caller local
the retention dataflow models as untouched). Correct: -O0/-O1/-O2/-O3 agree,
FPC 3.2.2 agrees byte-for-byte, the by-ref control declines as designed, and
`test_inline_stmt_call.pas` asserts side-effect COUNT and ORDER with two
non-commuting effects rather than values alone.

**Then measured, and the result is negative:**

| | |
| --- | --- |
| call-statement declines | 67 -> 13 distinct functions |
| **`while` declines** | **102 -> 118** |
| `compiler.pas` retained | 170 -> 173 |
| `compiler.pas` -O3 code | +4096 bytes |
| **16 real example programs** | **0 changed. byte-identical.** |

**The `while` count RISING is the whole story.** Bodies that used to die at the
call statement now travel further and die at a loop instead. They did not become
inlinable; they failed later. 54 stopped declining at the call and 16 immediately
re-declined at a `while`, and of whatever remained, enough failed at a call SITE
(retention is per-proc; the splice still has to qualify where it is called) that
**not one of sixteen real programs emits a different byte.**

### The finding is bigger than this ticket

Two slices, chosen by two DIFFERENT criteria, both delivered ~nothing:

- **depth>1 non-leaf**, picked on the biggest BOUND (3.12x): changed 1 program of 13.
- **statement-level call**, picked on the biggest REACH (67 blocked functions):
  changed 0 programs of 16.

**So "reach beats bound" — the correction this ticket was filed under — is ALSO
not predictive.** A static count of bodies a validator rejects does not predict
delivered value any better than a microbenchmark ceiling did. Both are counts of
shapes that COULD be admitted; neither counts what is actually executed.

What would predict it is dynamic: how often a retained body is CALLED on a hot
path. Nothing here measures that, and both of tonight's slices are evidence that
the static proxies are exhausted. **The honest reading is that the inline
admission axis is close to saturated on real code** — the bodies worth inlining
are largely already inlined, and the remaining rejected shapes are rejected in
code that does not run hot.

**A third slice picked by a third static metric should not be attempted without
first measuring call-site frequency.** That is the ticket this one should spawn,
not another admission widening.

### If this is reverted, VALUE is the reason, not risk

Keep the two separable, because they are, and a future reader will otherwise
assume a reverted optimisation was unsafe. This slice is **proven safe**:
-O0/-O1/-O2/-O3 agree, FPC 3.2.2 agrees byte-for-byte, -O0/-O2 byte-identical on
`compiler.pas`, optfuzz 219 programs with 0 diffs and 0 o0-compile-skips against
that exact binary, `gate.sh quick` GREEN, and the by-ref control declines as
designed.

**It is a revert candidate purely because it delivers nothing measurable** — 0 of
16 real programs changed, and `compiler.pas`'s +3 retained bodies have never been
timed because no load-independent instrument exists on this host (no valgrind, no
qemu TCG plugins, and `perf` is DENIED rather than absent:
`kernel.perf_event_paranoid = 4` blocks even user-space counters). If that
instrument appears and shows nothing, revert it; the safety evidence above is not
what would be in question.
