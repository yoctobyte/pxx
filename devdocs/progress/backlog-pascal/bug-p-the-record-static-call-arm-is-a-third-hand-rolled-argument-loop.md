---
slug: bug-p-the-record-static-call-arm-is-a-third-hand-rolled-argument-loop
title: "The record static / advanced-record ctor call arm is a THIRD hand-rolled argument loop with none of the doors"
track: P
prio: 35
type: bug
status: open
owner: ""
created: 2026-09-09
found-by: frankS
tags: [methods, arity, records, array-of-const]
blocked-by: []
summary: "`pasparser_expr.inc`'s advanced-record ctor / static-method arm hand-rolls a THIRD argument loop, distinct from the two that bug-p-the-bare-self-call-in-expression-position-has-none-of-the-doors is extracting, and it has the same omissions. Measured 2026-09-09 at compiler fd01b434e7ff, `TR = record class function One(x: Integer): Integer; static; end`: `TR.One(1, 2, 3)` is ACCEPTED and answers 3 -- the arguments shifted -- and `TR.One()` is ACCEPTED and answers 12, uninitialised memory. fpc 3.2.2 refuses both. The loop is `while CurTok.Kind <> tkRParen do ParseExpr` with no bracket door (TryParseBracketArgForSlot), no bare-method-name door (TryDelphiBareProcArg), no arity pre-check and no ExpectCallRParen tail, so it cannot absorb an elided `array of const` either. FILED SEPARATELY AND ON PURPOSE: the bare-self extraction cannot reach it -- it is a different arm with a different receiver shape -- so closing that ticket must not read as closing the class. A second, narrower gap fell out of the same probe and is noted in the body: `class function Desc(const a: array of const): Integer; static` inside a RECORD is refused outright with `unknown type: const`, so the array-of-const doors cannot even be tested at this arm yet."
---

# The record static call arm is a third hand-rolled argument loop

```pascal
{$mode objfpc}{$modeswitch advancedrecords}
type TR = record class function One(x: Integer): Integer; static; end;
...
WriteLn(TR.One(7));         { 7   -- correct }
WriteLn(TR.One(1, 2, 3));   { 3   -- fpc: Wrong number of parameters }
WriteLn(TR.One());          { 12  -- fpc: Wrong number of parameters }
```

`pasparser_expr.inc`, the arm around the `rcCi` / `rcMmi` / `rcSelf` locals:

```pascal
if CurTok.Kind = tkLParen then
begin
  Next;
  while CurTok.Kind <> tkRParen do
  begin
    ParseExpr;
    ...
  end;
  Expect(tkRParen, ')');
end;
```

Unbounded, `ParseExpr` only, `Expect` rather than `ExpectCallRParen`.

## Why it is a separate ticket

[[bug-p-the-bare-self-call-in-expression-position-has-none-of-the-doors]] is
extracting the two IMPLICIT-SELF loops into one routine. This is a third loop
on a different arm — a qualified receiver that is a record TYPE NAME, reached
through the ctor/static path — and the extraction does not pass through it. If
it is not written down, the class closes on paper while the third copy keeps
its holes, which is precisely the failure the parent ticket documents happening
five times in a row.

Whoever takes it should almost certainly route this arm through the same shared
routine rather than porting the doors a fourth time, but the Self handling
differs (`UMthNoSelf` / a lifted record temp / a `-1` self, per `73e05b3e1`), so
it is not a one-line substitution and that is the work.

## The narrower gap the probe hit first

```pascal
type TR = record
  class function Desc(const a: array of const): Integer; static;
end;
```
`pascal26:5: error: unknown type: const` — `array of const` is not accepted as a
parameter of a record method at all. So the bracket and variadic-tail doors
cannot be exercised at this arm until that is fixed, and the arity rows above
are what is measurable today. Not split into its own ticket because it is one
sentence and the same file; measure it again before assuming it is still true.

## How it was found

frankH asked, in a claim-collision handover, whether the record-static arm one
page up in the same file shares the loop being extracted. It does not. The
question is the whole finding — the answer took one probe.
