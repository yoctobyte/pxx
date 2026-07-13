---
prio: 45
---

# FPC's own TPoint parses, but its METHODS do not resolve

- **Type:** bug (compat)
- **Track:** P — Pascal frontend
- **Status:** done
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


## 2026-07-13 — record PROPERTIES landed, and they were NOT the cause
While chasing this, `property` inside a record turned out to be unsupported at all
(`Expected: :, but got: write`). FPC's own typshrdh.inc declares TSize and TRect as records
WITH properties, so that was a real gap and is now fixed (field-backed properties; read and
write both work; the accessor `read`/`write` are TOKENS, not identifiers, which is why a
tkIdent test silently never matched).

**But TPoint still fails identically.** So the property gap was not the cause either. Ruled
out so far, all verified by reproduction:
- the record parser and advanced records (methods, OVERLOADED methods, ctors, class operators,
  properties — every shape TPoint uses, all working standalone);
- a record with methods declared in a UNIT;
- a record with methods pulled in via `{$i}` inside a unit's type section;
- a record with methods inside the `{$else}` branch of a conditional, via `{$i}`;
- `{$endif <NAME>}` with a trailing identifier.

Each of those was built as a minimal reproduction of the real declaration and each COMPILES
AND RUNS. Something about the real types.pp/typshrdh.inc still eats the tail of TPoint's body
before the parser sees it.

Next: stop reproducing and go the other way — bisect the REAL typshrdh.inc/types.pp by cutting
it down until the failure disappears.


## 2026-07-13 — the include now parses IN FULL; the UNIT path is the remaining difference

Bisected the real file instead of reproducing it, as the previous note said to. Including the
REAL `typshrdh.inc` directly into a program now parses **completely** — every one of TPoint's
and TRect's declarations. Getting there needed four genuine gaps closed, each one real and now
landed:

- `ValReal` was not a known type name;
- DEFAULT PARAMETER VALUES on a record method (`Normalize: Boolean = False`);
- METHOD-BACKED record properties (`read getHeight write setHeight` — TRect uses them, TSize is
  field-backed);
- open-array params, which are still rejected loudly
  ([[bug-pascal-open-array-param-in-record-method]] — they segfaulted).

The only error left when including it directly is `unresolved forward: TPoint.Offset`, which is
CORRECT: typshrdh.inc is headers only; the bodies live in typshrd.inc.

**But going through `types.pp` as a UNIT still truncates TPoint's body.** Same include, same
content — parses in full from a program, loses everything after the fields when reached through
the unit. That is now the whole remaining question, and it narrows this from "something eats
tokens" to "the UNIT interface path eats tokens that the program path does not".

Next: diff the two paths. The unit interface is where to look (a pre-scan / DeclItem excision
that the program path does not run, or runs differently).

## 2026-07-13 — RESOLVED. It was never a compiler bug: OUR types.pas shadows FPC's.

Dumped the raw token stream around TPoint's body instead of the parser's view of it. The
tokens are:

```
tok[13468] TPoint  tok[13469] =  tok[13470] record
tok[13471] X  : LongInt ;  Y : LongInt ;  end ;
tok[13481] PSmallPoint = ^ TSmallPoint ;
```

That is **not typshrdh.inc's TPoint**. No `packed`, no `public`, no methods, and TSmallPoint
comes *after* it instead of before. Nothing excised anything.

`uses types` resolves to **our own `lib/rtl/types.pas`** — the RTL is on the default unit path,
so it wins over `-Fu.../objpas`. Our types.pas declared a plain `TPoint = record X, Y: LongInt;
end;`. FPC's `types.pp` was never parsed at any point in this investigation. The methods "were
not registered" because they were never written.

The three earlier hypotheses in this ticket (anonymous-record branch, conditional-compilation
excision, unit-interface pre-scan) were all wrong, and each was a guess dressed up as a lead.
The lesson is the same one as [[project_decl_order_soffset_not_token_index]]: **when a parser
"loses" something, dump the TOKENS before theorising about the parser.** One token dump ended a
hunt that four rounds of minimal reproductions could not, precisely because a reproduction can
only ever confirm the file you *think* is being read.

### What actually landed
Our `lib/rtl/types.pas` now declares TPoint, TSize and TRect as the ADVANCED RECORDS they are in
FPC — which the four real gaps closed while chasing this (ValReal, default params on record
methods, method-backed record properties, record properties at all) now make possible:

- `TPoint`: `SetLocation`/`Offset` (each overloaded on `(x, y)` and `(const TPoint)`), `IsZero`,
  `Add`, `Subtract`;
- `TSize`: `Width`/`Height` properties over `cx`/`cy`;
- `TRect`: `GetWidth`/`GetHeight`/`IsEmpty`/`Contains` + `Width`/`Height` properties.

Regression `test/test_types_point_methods_b269.pas` covers the whole path: record methods reached
through a UNIT, overload dispatch, a by-ref `Self` that really mutates the receiver, record-typed
results, and properties over fields.

So the ticket's original symptom (`p.Offset(q)` failing after `uses types`) now WORKS — just for
a reason nobody predicted.

### Resolution
Resolved. Not a compiler bug; a missing RTL declaration. The four gaps it flushed out were real
and are landed independently, which is the whole value this ticket produced.

## Log
- 2026-07-13 — resolved, commit pending.
