---
prio: 55
track: P
status: open
summary: "`Outer := 99` written inside a nested FUNCTION assigns the NESTED function's result, not the enclosing one. ParseNestedRoutine rewrites the enclosing function's name to the token `Result`, which is correct for a nested PROCEDURE (no result of its own) and wrong for a nested FUNCTION, where that token now names a different variable. Today it is LOUD when the two result types differ (`cannot assign Integer to AnsiString`) and SILENT when they agree. Measured identical on pin v407 and at HEAD 14d483f74974, i.e. unchanged by the capture fix in bug-p-a-sibling-call-to-a-capturing-nested-function-gets-the-wrong-capture-actuals."
---

## Repro

```pascal
program p2;
{$mode objfpc}{$H+}
function Outer: LongInt;
  function Inner: AnsiString;
  begin
    Outer := 99;           { the enclosing name, inside a nested FUNCTION }
    Result := 'x';         { and the nested function's own result }
  end;
begin
  Result := 1;
  WriteLn('inner=', Inner);
  WriteLn('outer=', Result);
end;
begin WriteLn('final=', Outer); end.
```

| | |
| --- | --- |
| fpc 3.2.2 | `inner=x` / `outer=99` / `final=99` |
| pxx, pin v407 and HEAD `14d483f74974` | `pascal26:6: error: incompatible types: cannot assign Integer to AnsiString` |

## Where

`ParseNestedRoutine`, `compiler/pasparser_decl.inc` (the block whose comment
starts *"Rewritten to `Result`"*). The rewrite fires when the token spells the
enclosing routine's unqualified name AND the next token is `:=`:

```pascal
Tokens[i].SOffset := NestStrOff('Result');
Tokens[i].SLen := 6;
nm := 'Result';
```

## Why it is not a one-liner

**Two different variables are spelled `Result` inside a nested function.** The
enclosing result is reachable only through this rewrite, and the rewrite's
target is the one name the nested function already owns. Since
`14d483f74974` a nested FUNCTION's `Result` is deliberately NOT captured, so
there is no lifted parameter to aim the rewrite at either — the enclosing result
needs a **distinct spelling** (a synthesized name, captured by reference like
any other enclosing local) before the rewrite can mean anything in a function.

**THE VISIBLE ERROR IS THE SAFE HALF, AND A NAIVE FIX LOSES IT.** With the two
result types differing the compiler refuses, which is the behaviour above. Make
them agree — `function Inner: LongInt` — and pxx compiles it and writes
`Inner`'s result instead of `Outer`'s, printing `outer=1` where fpc prints
`outer=99`. Any change here must be checked against BOTH, and a probe whose two
result types agree cannot see the difference.

## Not this ticket

`Outer.FV := 33` — a QUALIFIED write of the enclosing name — is a different
failure with a different cause (the rewrite is gated on the next token being
`:=`, so a qualified write is read as a recursive CALL and the program spins).
[[bug-p-a-qualified-enclosing-function-name-in-a-nested-routine-recurses]]

## Regression assertion in place

`test/test_a_nested_functions_own_result_is_not_the_enclosing_ones.pas`
(`test_nestownres26`) documents this row in its header as deliberately NOT
asserted, so whoever takes this ticket has the surrounding behaviour pinned.
