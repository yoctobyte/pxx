---
slug: bug-p-a-delphi-parenless-method-reference-cannot-have-a-chained-receiver
title: "Delphi mode: `F := TG.Create.Foo` -- a parenless method reference whose receiver is a CHAIN -- is parsed as a call"
track: P
prio: 45
type: bug
blocked-by: []
status: open
owner: ""
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
