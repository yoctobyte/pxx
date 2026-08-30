---
track: A
prio: 40
type: bug
blocked-by: []
summary: "`nested routine: capture of fixed-size array 'x' not yet supported` — the lambda-lift machinery in pasparser_decl.inc:6701 captures scalars and DYNAMIC arrays by reference but refuses a fixed-size one, because a lifted param carries capTk/capArr/capDyn and has nowhere to put the array's length and low bound. Blocks refactor-a-the-durable-param-row-is-hand-copied-on-three-registration-paths, where 21 fixed-size staging arrays are the exact thing a helper would need to see."
status: new
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
