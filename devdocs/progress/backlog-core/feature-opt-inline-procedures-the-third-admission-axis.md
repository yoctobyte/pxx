---
track: A+O
prio: 35
type: feature
status: backlog
owner: unassigned
blocked-by: []
found: 2026-09-05
found-by: frank-optimize, pricing the parked fork of feature-opt-nilpy-container-subscript-is-15-19x-slower-than-cpython
summary: "The inliner has NEVER inlined a procedure, at any -O level, however trivial the body: TryRetainInlineBody opens with `if not Procs[procIdx].IsFunc then Exit`. Measured with identical bodies -- `function AddF(a,b)` inlines at -O3 while `procedure SetG(v); begin g := v; end` is not even retained. This is a THIRD admission axis (is-function) alongside return type and body shape, and no other ticket names it. Bounded by measurement at 1.43x in the slot-op shape (six calls per iteration, 0.200s -> 0.140s, ~3.3 ns per call) -- so it is real, general, and NOT the fix for the NilPy subscript gap it was found under, where the classification compares are worth 2.80x more than the call removal."
---

# The inliner accepts only functions — procedures are a third admission axis

- **Type:** feature (optimizer — **Track O**, file-owned by **Track A**).
- Found 2026-09-05 while pricing the parked fork of
  [[feature-opt-nilpy-container-subscript-is-15-19x-slower-than-cpython]].

## The measurement

Identical bodies, one a function and one a procedure, `-O3`:

```pascal
function  AddF(a, b: Integer): Integer;         begin AddF := a + b; end;
procedure SetG(v: Integer);                     begin g := v; end;
```

`call AddF` is gone; `call SetG` remains. `PXXDBG=a.inline` shows **only
`AddF` retained** — the procedure is rejected at retention, so no shape
validator ever sees it. `TryRetainInlineBody`:

    if not Procs[procIdx].IsFunc then Exit;

## Why this is its own axis and not part of an existing ticket

The inliner's admission has three independent gates:

| axis | governed by | ticket |
| --- | --- | --- |
| return TYPE | `InlineScalarTk` | `feature-opt-inline-float-and-record-returning-leaves` (float half landed ec95c2beb; record half open) |
| body SHAPE | `InlineExprSimple` / `TryRetainInlineStmtBody` | `feature-inline-nonleaf-and-branch-locals` |
| **is-FUNCTION** | the line above | **none — this ticket** |

`feature-inline-nonleaf-and-branch-locals` extends shape (branch bodies,
while/for, deeper non-leaf) but every shape it discusses is inside a *function*.
Nothing widens the first gate.

## What it is worth, measured — and what it is NOT worth

A slot-op-shaped microbench (small branchy procedure writing through a pointer
param, six calls per iteration), `-O3`, min-of-5 interleaved, contended box:

| | | |
| --- | --- | --- |
| out-of-line calls | 0.200 s | 1.00x |
| hand-inlined | 0.140 s | **1.43x** |
| no dispatch at all | 0.050 s | 4.00x |

**1.43x in this shape, ~3.3 ns per call.** Read the third row before ranking
this: in the workload it was found under, removing the *calls* recovers 1.43x
while removing the *classification* recovers 2.80x more. **Do not take this
ticket expecting to close the NilPy subscript gap** — that is option 3 there,
and it is a frontend type-inference question, not an inliner one.

Its value is instead **general**: procedures are everywhere, and none of them
has ever been inlinable. That generality is unmeasured, and measuring it is the
first step of taking this ticket, not an assumption to start from
(the ~37%-advertised / ~5-7%-delivered campaign is the standing warning).

## Scope sketch, smallest useful slice first

A procedure has no Result, so the Result placeholder machinery does not apply
and the rest of the splice does. The natural first slice is **by-value scalar
params, straight-line assignment bodies** — which `SetG` already is.

Note what that slice does NOT reach, and why the slot ops need more: a `var`
param is `IsRef` and rejected outright, and `PyVarSlotClear(dst: PPyVarRec)`
writes through `dst^`, which `InlineExprSimple` rejects as a deref. So the
slot-op shape needs by-ref params or deref-target assignment on top. Slice the
ticket accordingly rather than promising the slot ops from the start.

## Gate

Track O's two: PROMISE measured as delivered value on a real workload (not a
census of how many procedure calls exist), PROOF from Track T's full tier.
Behind `-O3` first. **`tools/optfuzz.sh` is the designated net for splice
machinery** — it covers this one, unlike the float axis, since pasmith generates
integer procedures freely
([[bug-t-pasmith-returns-only-integer-kinds-so-optfuzz-is-blind-to-the-return-type-axis]]).
