---
track: A
prio: 40
type: bug
blocked-by: []
summary: "FIXED 2026-08-31 by feature-nested-routine-fixed-array-capture (50fcbddef + 29704fd69 + 416cbc997) — same bug, filed twice under two slugs. 1-D fixed arrays capture; MULTI-DIMENSIONAL is still refused, deliberately, and that half of this ticket's gate is NOT met. Was: `nested routine: capture of fixed-size array 'x' not yet supported` — the lambda-lift machinery in pasparser_decl.inc:6701 captures scalars and DYNAMIC arrays by reference but refuses a fixed-size one, because a lifted param carries capTk/capArr/capDyn and has nowhere to put the array's length and low bound. Blocks refactor-a-the-durable-param-row-is-hand-copied-on-three-registration-paths, where 21 fixed-size staging arrays are the exact thing a helper would need to see."
status: done
owner: ""
---

# A nested routine cannot capture a fixed-size array

- **Type:** bug / missing feature — **Track A** (`compiler/pasparser_decl.inc`).
- **Found:** 2026-08-30 (frankS) while collapsing three copies of the durable
  param row into one nested procedure. Filed rather than worked around, per
  CLAUDE.md's platonic-code rule; the reshaping it would have forced (a 23-arg
  signature of same-typed `var` array params, where a transposition type-checks)
  is a new fail-silent introduced to remove an old one.

## Repro

```pascal
procedure Outer;
var a: array[0..3] of Boolean;
  procedure Inner(i: Integer);
  begin
    if a[i] then WriteLn('x');       { <- refused }
  end;
begin
  a[0] := True; Inner(0);
end;
```

```
pascal26:N: error: nested routine: capture of fixed-size array 'a' not yet supported
```

A **dynamic** array in the same position compiles and works.

## Where

`compiler/pasparser_decl.inc:6701`. Capture lifts the nested routine to top
level and passes each captured local as a by-reference parameter, described by
`capTk` / `capRec` / `capArr` / `capDyn`. The dynamic arm sets
`capArr := True; capDyn := SymDynDepth[sidx]`. A fixed array has no `capDyn`
and the descriptor set has no slot for its `ArrLen` / `ConstVal` (low bound), so
the lifted parameter could be declared but not indexed correctly — hence the
honest refusal rather than a wrong lowering.

## Fix sketch

Add `capArrLen` / `capArrLo` alongside the existing descriptors, populate from
`Syms[sidx].ArrLen` / `Syms[sidx].ConstVal`, and have the lifted-parameter
synthesis emit a fixed-array `var` param. Three touch points: the capture
descriptor here, the synthesized declaration, and the call-site argument. The
refusal must stay for any shape the third point cannot express — a wrong
lowering here indexes the caller's frame.

## Gate

`make compiler/pascal26` + the repro above compiling and printing `x`, + a
control where the nested routine WRITES through the captured fixed array and
the caller observes it (by-reference capture, not a copy), + a multi-dimensional
and a non-zero-low-bound case (`array[1..3]`), since the low bound is the field
the current descriptor set is missing.

---

## Resolution (frankS, 2026-08-31) — a duplicate, and only three quarters of the gate

This is the same bug as `feature-nested-routine-fixed-array-capture`, filed
2026-07-11 from Track B. I filed this one on 2026-08-30 without noticing, then
implemented it on 2026-08-31 concurrently with another Track A session that had
taken the older slug — so the same bug was worked three times before anyone
looked at the other's ticket. **That is the finding worth keeping here**, more
than the fix: two of the three collisions were searchable. The older ticket's
title says "fixed-size array", this one's says "fixed-size array", and neither
`ready` nor `next` deduplicates by subject.

The fix landed under the other slug and matches this ticket's own fix sketch
almost line for line (`LiftCapFixedLen` / `LiftCapFixedLo` alongside the
existing `capTk`/`capArr`/`capDyn` descriptors, populated from
`Syms[].ArrLen` / `Syms[].ConstVal`, replayed onto the lifted param's
`pFixedLen`/`pFixedLo`).

### Against this ticket's Gate, item by item

| gate item | status |
| --- | --- |
| the repro compiles and prints `x` | **met** — verified at HEAD |
| nested routine WRITES through the capture, caller observes it | **met** — `ReadWrite` and `ParamCapture` rows |
| non-zero low bound (`array[1..3]`) | **met** — `LowBound` row; this is the half that fails silently, exactly as this ticket predicted |
| **multi-dimensional** | **NOT met — still refused** |

The multi-dimensional refusal is deliberate and now says so:

```
error: nested routine: capture of multi-dimensional array 'a' not yet
supported (1-D fixed arrays are)
```

Nothing in either ticket's acceptance asked for it and no caller wants it: the
lift channel would need a SHAPE, not just a length and a bound. Not re-filed —
the diagnostic names the boundary, which is what a reader hitting it needs.

### What this unblocks

`refactor-a-the-durable-param-row-is-hand-copied-on-three-registration-paths`,
which is why I filed this in the first place: its 21 fixed-size staging arrays
are the exact thing a nested helper needs to see, and the reshaping the refusal
forced (a 23-arg signature of same-typed `var` array params, where a
transposition type-checks) was a new fail-silent traded for an old one. That
trade is off the table now.

## Log
- 2026-08-31 — resolved as a duplicate of
  `feature-nested-routine-fixed-array-capture`; multi-dimensional capture stays
  refused, deliberately.
- 2026-08-31 — resolved, commit 22da693a5.
