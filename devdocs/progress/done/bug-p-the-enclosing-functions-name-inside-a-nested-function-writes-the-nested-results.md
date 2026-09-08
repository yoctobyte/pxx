---
prio: 55
track: P
status: done
summary: "`Outer := 99` written inside a nested FUNCTION assigns the NESTED function's result, not the enclosing one. ParseNestedRoutine rewrites the enclosing function's name to the token `Result`, which is correct for a nested PROCEDURE (no result of its own) and wrong for a nested FUNCTION, where that token now names a different variable. Today it is LOUD when the two result types differ (`cannot assign Integer to AnsiString`) and SILENT when they agree. Measured identical on pin v407 and at HEAD 14d483f74974, i.e. unchanged by the capture fix in bug-p-a-sibling-call-to-a-capturing-nested-function-gets-the-wrong-capture-actuals."
owner: frankS
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

# FIXED — 2026-09-07 (frankS)

`compiler/pasparser_decl.inc`. The enclosing result now gets **its own spelling**
when the nested routine is a FUNCTION: the token is rewritten to `__outerres`
and the result is captured by reference under that name, while the ACTUAL
spliced at the call site stays `Result` — which is what it must be, since at the
call site that spelling still resolves to the enclosing function's result.

**Two names for one capture, and that is the whole mechanism.** Every other
capture uses one spelling in both positions (`capActOff`'s own comment says so),
so `capActNm[]` is a new parallel column beside `capNm[]` that defaults to it.
Exactly one capture ever differs.

## Both faces asserted, because either probe alone is blind

| row | before | fpc |
| --- | --- | --- |
| result types DIFFER | `cannot assign Integer to AnsiString` | `diff = x 99` |
| result types AGREE | compiled, printed `same = 7 1` — **silent wrong write** | `same = 7 99` |

The ticket warned about this and it is worth restating: a probe whose two result
types agree cannot see the first face, and one whose types differ cannot see the
second. Fixture
`test/test_the_enclosing_functions_result_written_from_a_nested_function.pas`
(`test_outerres26`) carries both, plus the control that the nested function's own
`Result` is still its own (it reads BOTH variables, so the row cannot pass with
them swapped).

## It also retires the sibling fix's deliberate exclusion

`F.FV := 33` from a nested FUNCTION was excluded by
[[bug-p-a-qualified-enclosing-function-name-in-a-nested-routine-recurses]],
because rewriting it to `Result` would have traded an unbounded recursion for a
silent wrong write. With a distinct spelling it is simply correct, and row 3
asserts it. The condition in the rewrite is now one token-kind set for both
nested-routine flavours.

## Measured and deliberately NOT changed

- **An ARRAY-valued enclosing result** is not captured this way. A captured array
  needs its shape carried (`capArr`/`capDyn`/`capFixedLen`/`capFixedLo`, three
  arms at the ordinary capture site) and a result sym is not where that was
  measured from, so such a function keeps today's behaviour rather than an
  untested one.
- **A BARE read** of the enclosing name inside a nested routine (`Inner := F`,
  parameterless) is a recursive CALL here and the RESULT VARIABLE in fpc.
  Decisive probe is a call COUNTER, because the returned values can coincide:
  fpc `calls=1`, pxx `calls=2`, pin v407 `calls=2`. Predates this work. Filed as
  `bug-p-a-bare-enclosing-function-name-read-in-a-nested-routine-recurses` —
  it is a dialect decision, not a token kind to add.

## Residual this design keeps, unchanged

An actual is spliced AS A NAME and resolved in the CALL SITE's scope, so a call
from a SIBLING nested function passes that sibling's `Result`. Pre-existing for
every capture — a nested PROCEDURE capturing `Result` has the same hole — and it
is [[bug-p-a-sibling-call-to-a-capturing-nested-function-gets-the-wrong-capture-actuals]].

## Stale note corrected in the same commit

`test/test_a_nested_functions_own_result_is_not_the_enclosing_ones.pas` listed
this row and the qualified-write row as "NOT ASSERTED HERE". Both are fixed now,
and "not asserted" reads as "still broken" to the next reader, so the list is
corrected in place rather than deleted.

## Log
- 2026-09-08 — resolved; this names the commit that carried the resolve, which is not always the one that carried the change — commit 1245a51e5.
