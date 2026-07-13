---
prio: 45
---

# FPC's own TPoint parses, but its METHODS do not resolve

- **Type:** bug (compat)
- **Track:** P — Pascal frontend
- **Status:** backlog — opened 2026-07-13.
- **Follows:** [[feature-pascal-advanced-records]] / [[feature-pascal-record-constructors]]

## Symptom
```pascal
uses types;
var p, q: TPoint;
begin
  p.X := 3;            { fields work; SizeOf(TPoint) = 8 }
  p.Offset(q);         { error: Expected: :=  — Offset is not seen as a method }
```
The parse of `types.pp` / `typshrdh.inc` SUCCEEDS and the record's FIELDS are usable — only
its methods are missing, i.e. the member-call path finds no UMeth and falls back to treating
`p.Offset` as a field assignment.

## What is NOT the cause (verified)
Our own advanced records are fine, including every shape TPoint uses:
- methods, and OVERLOADED methods (`Offset(const o: TPt)` + `Offset(dx, dy: Longint)`) —
  both resolve and dispatch correctly;
- constructors;
- `class operator` (`+`, `=`);
- `class function ... static; inline;` directives.

So it is not advanced records as such. Something specific to how typshrdh.inc's TPoint is
reached or parsed leaves its methods unregistered.

## Leads
- TPoint's head is split by a conditional: `TPoint = {$ifndef FPC_REQUIRES_PROPER_ALIGNMENT}
  packed {$endif} record` — check the named-record branch actually takes it (vs. routing to
  ParseTypeKind's ANONYMOUS record path, which would mint an unnamed UCls row: fields would
  still work through the alias, methods would attach to nothing the call site can find).
  That would explain the symptom exactly.
- `function Distance(const apt: TPoint): ValReal;` — `ValReal` is not a known type name. With
  the unknown-type check now strict this should ERROR, and it does not, which is itself a
  clue that this part of the body is not being parsed.

## First step
Instrument the named-record branch for TPoint (does AddUClass run? does ParseRecordFields see
the method tokens?), as was done for the unknown-type hole — do not guess.

## Gate
`make test` + self-host byte-identical.
