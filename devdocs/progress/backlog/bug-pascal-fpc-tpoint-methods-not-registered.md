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

## INSTRUMENTED 2026-07-13 — the tokens are GONE before the parser sees them

Both leads above are WRONG. Instrumented instead of guessing:

```
DBG named-record TPoint ci=4          <- the NAMED record branch IS taken (not anonymous)
DBG loop tok kind=1 sval=X            <- ParseRecordFields sees field X
DBG loop tok kind=1 sval=Y            <- ...and field Y
DBG TPoint methcount=0                <- ...and then EXITS: CurTok is already `end`
```

`ParseRecordMethodDecl` is never called. The record-body loop never sees `public`, never sees
a single method — **those tokens are not in the token stream at all** by the time the record
parser runs.

So this is NOT the record parser and NOT advanced records. Something EXCISES the tail of
TPoint's body (from `public` onward) before parsing. That is the bug.

Also ruled out: `{$endif <NAME>}` (an `$endif` with a trailing identifier, which typshrdh.inc
uses) parses correctly — verified with a standalone test.

## Next step
Find what removes those tokens. Candidates, in order:
- the declaration PRE-SCAN / excision machinery (it renumbers and removes token spans — see
  the SOffset-vs-token-index landmine in [[project_decl_order_soffset_not_token_index]]);
- the conditional-compilation handling around TPoint's `{$ifdef VER3}` block (VER3 IS
  defined under `--mimic-fpc` — verified — so that block should be KEPT, and a bug that drops
  it might drop more).

Dump the token stream around TPoint (or print tokens as ParseRecordFields walks) and find
where `public` goes.

## Gate
`make test` + self-host byte-identical.
