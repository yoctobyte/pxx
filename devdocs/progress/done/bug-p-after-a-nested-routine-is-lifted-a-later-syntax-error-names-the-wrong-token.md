---
track: P
prio: 40
type: bug
blocked-by: []
status: done
owner: frankS
created: 2026-09-06
summary: "FIXED 2026-09-08. BOTH halves were the same missing list, and the quiet half was the real one: `{$R+}` was NOT in force inside a lifted nested routine's body -- measured, an out-of-range subrange store went through and the program continued where fpc 3.2.2 raises Runtime error 201. The ticket warned against guessing which of CurTok/TokPos had moved and the answer is NEITHER: the lift is a THIRD token mover and it carried the TRawToken alone. ParseNestedRoutine deletes the in-place body with a hand-written `Tokens[i - remCount] := Tokens[i]` loop instead of RemoveTokens, so ShiftTokParallel never ran and every token after the lift read its SPELLING from the slot the deleted body used to occupy -- hence the right line, the wrong token, and a window remCount positions early. FlushPendingNestedProcs appends the stash with the same gap. Fixed by ShiftTokParallel at the delete, zeroing the two synthesized `forward ;` slots, and StashTokParallel/UnstashTokParallel carrying all thirteen channels through the side buffer. The ticket's doubt (`TC.Later`'s tokens are at their ORIGINAL indices) was the one wrong step: they are not -- everything after the deleted body moves DOWN by remCount, which is exactly the offset observed."
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

## 2026-09-08 — fixed, and the quiet half was the real one

### The mechanism, measured rather than guessed

Neither `CurTok` nor `TokPos` moved. **The lift is a THIRD token mover and it was
not in `ShiftTokParallel`'s audit**, exactly as this ticket's own "what is
established" section suspected — and the reason that section then doubted itself
is the one wrong step in it:

> *"The repro's failing token is in `TC.Later`, whose tokens are at their
> ORIGINAL indices and were never stashed."*

They are not at their original indices. `ParseNestedRoutine` deletes the in-place
body with a hand-written loop —

```pascal
for i := finalCur to TokCount - 1 do
  Tokens[i - remCount] := Tokens[i];
```

— so **everything after the lifted routine moves DOWN by `remCount`**, and that
is precisely the offset the `near:` window was off by. It is a hand-written
remove rather than a `RemoveTokens` call, which is where `ShiftTokParallel` would
have come from for free.

### The half that was not cosmetic, now measured

```pascal
{$R+}
procedure Checked(k: LongInt);
  procedure Inner(n: LongInt);
  var v: 1..9;
  begin v := n; WriteLn('not reached ', v); end;
begin Inner(k); end;
```

| | |
| --- | --- |
| fpc 3.2.2 | `Runtime error 201`, exit 201 |
| pxx before | prints `not reached 20`, exit 0 |

**A lifted body ran under whatever directive state sat at the appended token
indices.** The positive control matters here: the identical store in a
NON-nested routine traps correctly, so this is the lift and not `{$R+}`.

### Fix

- `ShiftTokParallel(hdrEnd + 3, -remCount)` before the hand-written delete, with
  the old `TokCount` still in place, which is that procedure's stated contract.
- The two synthesized `forward ;` tokens get their spelling channels zeroed —
  their `TRawToken` spans were already cleared and the parallel slots still held
  the body tokens they displaced, the same defect one array over.
- `StashTokParallel` / `UnstashTokParallel` (lexer.inc, beside
  `ShiftTokParallel`) carry all thirteen channels out to `PendNest*` and back at
  the flush. Spellings are carried VERBATIM, not zeroed: these are real tokens
  the programmer wrote, moved rather than synthesized.

Three copies of one list now (`EnsureTokCapacity`, `ShiftTokParallel`,
`StashTokParallel`), all in `lexer.inc` and all cross-referenced, for the reason
this file already gives about keeping the first two together.

### Gate

`test/test_a_lifted_nested_routine_keeps_its_token_channels.pas` — the `{$R+}`
arm traps, the `{$R-}` arm prints (the control: a fix that turned range checking
on everywhere passes without it). A SUBRANGE store rather than an array index, so
the unchecked arm prints a value instead of corrupting memory and the two arms
differ by a diagnostic rather than by luck.
`..._diag.pas` must NOT compile, and the Makefile greps the diagnostic TEXT and
the window — a compile-only row cannot see a wrong spelling, and the LINE was
right all along, which is what made this look cosmetic.

## 2026-09-08 (later) — the same class has a SECOND live site, and the audit that found it

The handle is not a phrase. It is the operation: **what moves tokens?**

```
grep 'Tokens\[..\] := Tokens\[' compiler/*.inc
```

Five hits outside `lexer.inc`. Grepping CALLERS of `RemoveTokens` /
`InsertTokens` finds none of them, by construction — an open-coded move is not
a caller, which is what makes this rung of the absent-copy shape unreachable by
enumeration.

**`ParseOperatorDef` (`pasparser_call.inc`) is two of the five**, both in the
Pascal lane, both calling `AdjustSrcRanges` and neither calling
`ShiftTokParallel`: a 2-token INSERT of the synthesized `function <synName>`
header, and a 1-token REMOVE of the `r :` pair for a named operator result.

```
plain operator          expected 'then' before 'WriteLn'   <- +2, the insert width
named-result operator   expected 'then' before 'then'      <- +1, insert 2 remove 1
no operator (control)   expected 'then' before '2'
```

**The magnitude named the cause a second and third time before any code was
read**, and it also separates the two movers, which is why both arms are
fixtures rather than one.

Not claimed: a directive-state instance for this site. The lift's shift is
`remCount` — dozens of tokens, easily spanning a `{$R}` boundary — while this
one is 2, and a `{$R+}`-after-an-operator probe traps correctly in both
compilers. Same mechanism, same fix, only the spelling half measured here.

### The remaining three hits — measured, and LATENT rather than live

Tracks R and Z, both experimental. Examined rather than left as a list, because
"not examined" in a closing section is how the next reader inherits a guess.

- **`rparser.inc:3677`** — a compaction pass that STRIPS `pub` tokens from the
  whole stream before parsing, moving `Tokens[]` down by a variable stride and
  the parallel arrays not at all. It is the real one of the three by shape, and
  it does not fire today: probed with `struct P { pub a: i64, pub b: i64 }` and a
  deliberate expression error after it, against the same file with `pub`
  removed, and **both windows are identical** — because the Rust lexer does not
  populate `TokSrcOff`/`TokSrcLen` in the first place (the `near:` window prints
  no punctuation in either case, which is the pre-`RecordTokSpan` shape).
  **Shifting an empty channel is a no-op**, so the site is latent: it becomes
  live the day `rlexer` records spans, and whoever does that owns this.
  Note the stride is variable, so it needs the parallel arrays compacted inside
  the same loop — `ShiftTokParallel` does not apply.
- **`rparser.inc:5619` and `zparser.inc:1914`** — APPENDS of a specialized
  generic function body at `TokCount`, not moves. The destination channels are
  untouched capacity, so `TokSrcLen` is 0 and `WriteTokenContext` falls back to
  the raw token's own `SOffset`/`SLen`, which is correct for these. Same
  deliberate answer the Pascal specializer's splice documents. No defect.

Neither track's gate was run for this; nothing in either was changed.
