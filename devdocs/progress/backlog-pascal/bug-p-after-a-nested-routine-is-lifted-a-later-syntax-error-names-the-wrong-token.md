---
track: P
prio: 40
type: bug
blocked-by: []
status: open
owner: ""
created: 2026-09-06
summary: "Once any nested routine has been lambda-lifted, every LATER syntax error in the file reports the right LINE with the wrong token and the wrong `near:` window. Nine-line repro: `if q 2 then` on line 18 is reported as `pascal26:18: error: expected 'then' before 'q'` with `near: procedure TC . Later ; var >>> q : Integer` -- line 15's tokens. Without the nested routine the identical error reads `before '2'` with the right window. So CurTok (which supplies the line) and TokPos (which supplies both the name and the window) are out of step after a lift. WHICH of the two moved is NOT established and must not be guessed: this diagnostic cost a session an hour by sending it to a routine 128 lines from the actual defect, and a ticket that names the wrong mechanism would cost the next one the same."
---

# After a nested routine is lifted, a later syntax error names the wrong token

- **Type:** bug (diagnostic — but see the second half, which may not be) —
  **Track P** (`compiler/pasparser_decl.inc`, `compiler/lexer.inc`).
- Found while diagnosing fcl-passrc rung 7's `pscanner.pp:3806` wall
  ([[feature-pascal-corpus-passrc]]).

## Repro

```pascal
{$mode objfpc}
program spell;
type TC = class F: Integer; procedure Outer; procedure Later; end;
procedure TC.Outer;
  procedure Helper(AVeryDistinctiveName: Integer);   { captures F -> lifted }
  begin F := F + AVeryDistinctiveName; end;
begin Helper(1); end;
procedure TC.Later;
var q: Integer;
begin
  q := 1;
  if q 2 then WriteLn('x');       { the deliberate syntax error }
end;
var c: TC;
begin c := TC.Create; c.Outer; end.
```

```
pascal26:18: error: expected 'then' before 'q'
  near: procedure TC . Later ; var >>> q : Integer
```

The line is right. The named token is `q` and the offending token is `2`. The
window is anchored eleven tokens early, at line 15. **Delete the nested
routine and the identical error reads `before '2'` with the correct window.**

## What is established

- `Expect` reads its LINE from `CurTok.Line` and its SPELLING from
  `TokSrcOff[TokPos - 1]` / `TokSrcLen[TokPos - 1]`; `WriteTokenContext` reads
  the window from `TokPos` and the same two channels. **The line comes from one
  source and the name and window from the other, and they disagree.**
- The disagreement appears only after a lift. `ParseNestedRoutine` both
  REWRITES the in-place body to `forward ;` and STASHES the body into
  `PendNestTok`; `FlushPendingNestedProcs` appends the stash at `TokCount`.
- The stash loop copies `Tokens[i]` and **nothing else** — not
  `TokSrcOff`/`TokSrcLen`, not the seven directive-state channels
  ({$PACKRECORDS}, {$Q}, {$R}, {$I}, {$N}, {$SCOPEDENUMS}, {$ASSERTIONS}), not
  the two C attribute slots. The flush appends without touching them either.
  `ShiftTokParallel` (`lexer.inc`) exists precisely to keep those thirteen in
  step across a splice and says so at length — **the nested stash/flush is a
  THIRD token mover and it was never added to that audit.**

## What is NOT established, and please do not guess it

Whether the observed symptom is the stash/flush channel gap above, or a plain
`CurTok`/`TokPos` desync from the in-place `forward ;` rewrite, or both. The
repro's failing token is in `TC.Later`, whose tokens are at their ORIGINAL
indices and were never stashed — which the channel-gap explanation does not
obviously cover. I stopped at the measurement rather than reason past it.

**The reason for the warning is the ticket's own history.** This diagnostic
reported `3806: expected 'then' before 'UseOtherwise'` for a defect at 3806
whose token was `=`; `UseOtherwise` lives 128 lines away in a different
routine. Four repro attempts failed because they reproduced the construct the
message named. `PXXDBG=a.expect:*` settled it in one run — `want=16 got=64`,
tkThen against tkEq — and the real defect (`c1809b2ad`) had nothing to do with
any identifier. An hour, and the wrong-mechanism guess was the expensive part.

## The half that may not be cosmetic

The two spelling channels are the LOUD half. The seven directive states are the
quiet one, and `ShiftTokParallel`'s comment already spells out the consequence
for its own case: *"a {$R+} region's boundary moves by the splice width, and
range checking silently starts or stops at the wrong token."* If the stash/flush
gap is real, then **a lifted nested routine's body runs under whatever directive
state happens to sit at the appended indices** — `{$R+}`, `{$Q+}`,
`{$PACKRECORDS}` — rather than the state in force where it was written. No
instance measured; nobody has looked, which is the same sentence that preceded
the last one.

## Gate

A test asserting the ERROR TEXT of a deliberate syntax error placed after a
lifted nested routine (the repro above), plus one asserting `{$R+}` range
checking is in force inside a lifted nested routine's body and `{$R-}` is not.
A compile-only row cannot see either half.
