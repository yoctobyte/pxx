---
slug: bug-p-a-delphi-parenless-method-reference-cannot-have-a-chained-receiver
title: "Delphi mode: `F := TG.Create.Foo` -- a parenless method reference whose receiver is a CHAIN -- is parsed as a call"
track: P
prio: 45
type: bug
blocked-by: []
status: done
owner: frankuser
created: 2026-09-07
summary: "Delphi mode takes a method reference with NO `@` at all, and TryParseParenlessMethodRef (pasparser_call.inc) reads exactly `Ident . Ident`: the receiver may be a symbol, a class type or a metaclass variable, never an EXPRESSION. So `TG.F := g.Foo` works and `TG.F := TG.Create.Foo` gives `wrong number of parameters in call to TG.Foo`. The `@` spelling of the same chain was fixed 2026-09-07 (bug-p-a-method-reference-can-only-be-taken-through-one-selector) and this is its sibling, deliberately left: that arm parses SPECULATIVELY and must consume no tokens when it decides the shape is a call, so a chained receiver needs a rewind the depth-1 arms never needed. Walls tgeneric106.pp, which fpc compiles and runs. Fifth receiver spelling of bug-p-a-parenless-method-reference-handles-two-of-four-receiver-spellings (done)."
---

# Repro

```pascal
program dp1; {$mode delphi}
type
  TG = class
    X: Integer;
    class var F: function(const aX: Integer): TG of object;
    function Foo(const aX: Integer): TG;
  end;
function TG.Foo(const aX: Integer): TG;
begin Result := TG.Create; Result.X := aX; end;
var g: TG;
begin
  g := TG.Create;
  TG.F := g.Foo;              { works                                     }
  if TG.F(41).X <> 41 then halt(1);
  TG.F := TG.Create.Foo;      { pascal26: wrong number of parameters ...  }
  if TG.F(42).X <> 42 then halt(2);
  WriteLn('ok');
end.
```

fpc 3.2.2 prints `ok`. Measured 2026-09-07 at compiler `fcd2086f6780`.

**The depth-1 row is in the repro on purpose**: it passes, so the defect is the
receiver's SHAPE and not the parenless form.

# Where

`TryParseParenlessMethodRef`, pasparser_call.inc. It resolves `rci` from one of
three receiver spellings — a symbol whose `RecName` is a class, a class type
name, or a metaclass variable through `SymMetaclassCi` — and every one of them is
a single identifier. A chained receiver is a fourth thing: an expression whose
type is a class.

**Why it is harder than the `@` version.** The `@` arm is committed the moment it
sees the `@`, so it can parse the chain and decide afterwards. This arm is a
TRIAL: its own comment says *"committed: nothing below can fail, so no tokens are
consumed speculatively"*, and it must fall through with the stream untouched when
the shape turns out to be a call. Parsing `TG.Create` to find out what it is
allocates AST nodes and moves `TokPos`, so this needs a rewind (`trialProcMark`
/ `trialSymMark` and the AST arena floor are the existing machinery for that
kind of trial in ParseFactorCore) rather than a lookahead.

**Do NOT reach for `AtStopDotTok` alone.** It stops the walk in the right place
but says nothing about the trial: the tokens are still consumed.

# To burn

`tgeneric106.pp` — its objfpc twin `tgeneric107.pp` burned with the `@` fix, so
the two files are now a matched pair testing the two spellings, and 106 is the
only one left.

# RESOLVED

The trial-with-rewind the ticket asked for, plus one thing the ticket did not
predict and which cost the first build.

## The rewind

`LastDotOfDesignator` finds the last dot without consuming (it is a lookahead
and resolves no name, so it cannot be wrong about types, only about extent),
`AtStopDotTok` bounds the walk, and the four tables a trial parse dirties are
marked and restored on the failure path: `ProcCount`, `SymCount`, `FrameSize`,
`ASTNodeCount`, plus `TokPos` and `CurASTNode`/`LastExprTk`. Gated on the last
dot being deeper than the first, so every depth-1 designator reaches the
existing arms untouched.

It also had to run BEFORE those arms, which the ticket does not say: for
`g.Mk.Foo` the depth-1 arm finds `Mk`, commits to `g.Mk` as the reference and
strands `.Foo` — the same shape whose `@` twin used to die on `a statement
cannot start with '.'`.

## What the ticket missed: ParseFactor was the wrong walker for half the shapes

The obvious reading of the `@` sibling is "set the stop, recurse", and that is
what I built first. It fixed `TG.Create.Foo` and left `g.Mk.Foo` failing with
the identical original error.

**Only `ParseClassRecordSelectors` consults `AtStopDotTok`.** `ParseLValueAST`,
where `ParseFactor` sends a SYMBOL-rooted designator, has its own selector
handling and walks past the stop. The probe that named it was `g.Inner.Foo` — a
FIELD link rather than a method-call link, failing identically, which rules out
the link and leaves the root. The `@` arm at `pasparser_expr.inc` ~1180
hand-builds the receiver node for exactly this reason; its class-name sibling at
~1424 uses `ParseFactor` and says so. This arm needs both, because a trial does
not know the root shape before it looks.

That duplication is now four sites encoding one fact and is parked as
`refactor-p-atstopdottok-is-honoured-by-one-of-the-two-selector-walkers`
(prio 35, safe by construction, not attempted here).

## Verification

`test/test_delphi_parenless_methodref_chained_receiver.pas`, wired into
`test-core`, `.expected` generated from fpc 3.2.2:

| row | | |
| --- | --- | --- |
| 1 | `TG.F := g.Foo` | depth 1, the spelling that already worked |
| 2 | `TG.F := TG.Create.Foo` | the ticket's repro |
| 3 | `n := TG.Create.Bar` | **the rewind** — same token shape, and a CALL |
| 4 | `TG.F := g.Mk.Foo` | symbol root, the shape ParseFactor could not stop |
| 5 | `n := g.Mk.Bar` | the rewind one link deeper |

Rows 3 and 5 are the ones a happy-path fixture omits: with only 1, 2 and 4 no
rewind is ever requested, so the restore code would never run and the fixture
would pass with it deleted.

**Controls, run rather than assumed:** with the change reverted the fixture does
not compile (`wrong number of parameters in call to TG.Foo` at row 2) and
`tgeneric106.pp` fails at its own line 20. With it, both compile and RUN — 106
takes neither of its `halt` arms.

`tgeneric106.pp` burned from `test/pascal-conformance/pxx.skip`; its objfpc twin
`tgeneric107.pp` burned with the `@` fix, so the matched pair is complete.

Self-host fixedpoint converged (`75dc1e4e746b`).

## Log
- 2026-09-08 — resolved; this names the commit that carried the resolve, which is not always the one that carried the change — commit 7257f1213.
