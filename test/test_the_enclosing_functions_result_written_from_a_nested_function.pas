program test_the_enclosing_functions_result_written_from_a_nested_function;
{ `Outer := 99` INSIDE A NESTED **FUNCTION** WROTE THE NESTED FUNCTION'S RESULT.
  ParseNestedRoutine rewrites the enclosing function's name to the token
  `Result`, which is right for a nested PROCEDURE (it has no result of its own)
  and names a different variable inside a nested function.

  TWO FACES, AND ONLY ONE OF THEM WAS VISIBLE. With the two result types
  DIFFERENT the compiler refused -- `cannot assign Integer to AnsiString`, an
  error about types for a defect about scope. With them the SAME it compiled and
  silently wrote the wrong variable: row 2 printed `same = 7 1` where fpc prints
  `same = 7 99`. A probe whose two result types agree cannot see the first face
  and a probe whose types differ cannot see the second, so BOTH are rows here.

  THE FIX IS A SECOND NAME FOR ONE CAPTURE. The enclosing result is captured by
  reference like any other enclosing local, but under the synthesized parameter
  name `__outerres`, while the ACTUAL spliced at the call site stays `Result` --
  which is what it must be, since at the call site that spelling still resolves
  to the enclosing function's result. Every other capture uses one name in both
  positions; this is the one that cannot, which is why capActNm exists beside
  capNm and defaults to it.

  ROW 3 IS FREE AND IS ASSERTED ANYWAY. `F3.FV := 33` from a nested FUNCTION was
  the case the sibling fix
  ([[bug-p-a-qualified-enclosing-function-name-in-a-nested-routine-recurses]])
  deliberately excluded, because rewriting it to `Result` would have swapped an
  unbounded recursion for a silent wrong write. With a distinct spelling it is
  simply correct, and the exclusion is gone.

  ROW 4 IS THE CONTROL THAT THE NESTED FUNCTION'S OWN `Result` IS STILL ITS OWN:
  both variables are written in one body, and the row would pass just as well if
  they were the same variable in the wrong direction, so it reads BOTH -- 7 from
  Inner and 17 from Outer.

  MEASURED AND DELIBERATELY NOT CHANGED, one kind and one spelling.

  An ARRAY-valued enclosing result is not captured this way: a captured array
  needs its shape carried (three arms at the ordinary capture site) and a result
  sym is not where I measured that from, so such a function keeps today's
  behaviour rather than an untested one.

  And a BARE read of the enclosing name inside a nested routine -- `Inner := F`
  with no parentheses -- is a recursive CALL here and the RESULT VARIABLE in fpc.
  Decisive probe, a call counter: fpc says `calls=1`, pxx says `calls=2`, and pin
  v407 says `calls=2` too, so it predates this work and is untouched by it. Filed
  as bug-p-a-bare-enclosing-function-name-read-in-a-nested-routine-recurses.
  NOT a row here: asserting either answer would freeze a divergence this fixture
  is not about.

  The residual this design keeps, for every capture and not just this one: an
  actual is spliced AS A NAME and resolved in the CALL SITE's scope, so a call
  from a SIBLING nested function passes that sibling's `Result`. Pre-existing --
  a nested PROCEDURE capturing `Result` has the same hole --
  [[bug-p-a-sibling-call-to-a-capturing-nested-function-gets-the-wrong-capture-actuals]].

  All rows measured against fpc 3.2.2.
  bug-p-the-enclosing-functions-name-inside-a-nested-function-writes-the-nested-results }
{$mode objfpc}{$H+}
type TBox = class FV: LongInt; end;

{ 1. result types DIFFER — was `cannot assign Integer to AnsiString` }
function F1: LongInt;
  function Inner: AnsiString;
  begin
    F1 := 99;
    Result := 'x';
  end;
begin Result := 1; WriteLn('diff  = ', Inner, ' ', Result); end;

{ 2. result types AGREE — was silent: Inner's result was written, F2's was not }
function F2: LongInt;
  function Inner: LongInt;
  begin
    F2 := 99;
    Result := 7;
  end;
begin Result := 1; WriteLn('same  = ', Inner, ' ', Result); end;

{ 3. through a SELECTOR, from a nested FUNCTION }
function F3: TBox;
  function Inner: LongInt;
  begin
    F3.FV := 33;
    Result := 5;
  end;
begin Result := TBox.Create; Result.FV := 1; WriteLn('sel   = ', Inner, ' ', Result.FV); end;

{ 4. CONTROL: the nested function's own Result is still its own }
function F4: LongInt;
  function Inner: LongInt;
  begin
    Result := 7;
    F4 := Result + 10;
  end;
begin Result := 1; WriteLn('own   = ', Inner, ' ', Result); end;

begin
  WriteLn('r1    = ', F1);
  WriteLn('r2    = ', F2);
  WriteLn('r3    = ', F3.FV);
  WriteLn('r4    = ', F4);
end.
