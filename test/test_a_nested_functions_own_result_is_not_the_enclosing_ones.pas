program test_a_nested_functions_own_result_is_not_the_enclosing_ones;
{ TWO VARIABLES ARE SPELLED `Result` INSIDE A NESTED ROUTINE, and they were
  compiled as one:

    * a nested FUNCTION's `Result` is ITS OWN;
    * a nested PROCEDURE has no result, so its `Result` is the ENCLOSING
      function's -- measured against fpc 3.2.2, a nested procedure's
      `Result := ...` is still there when the enclosing function returns.

  THE ENCLOSING FUNCTION RETURNS A CLASS AND THE NESTED ONES RETURN LongInt, AND
  THAT IS THE WHOLE POINT. A nested function's own Result used to be captured as
  if it were the enclosing function's, snapshotted with the ENCLOSING type -- so
  a SIBLING call passed a LongInt where the lifted parameter said class:

    no overload of PeekIt$23 matches these arguments
      argument types: (LongInt, LongInt)
      candidates:  PeekIt$23(LongInt, class)

  Make the two result types AGREE and the bug becomes invisible -- the spurious
  capture is still made, but nothing can disagree with it. Every earlier
  reduction did exactly that and compiled cleanly, which is why this fixture
  deliberately makes them differ. A probe whose right answer equals its wrong
  answer is not a probe.

  NOT ASSERTED HERE, and both measured identical on pin v407 and at HEAD, i.e.
  neither fixed nor worsened by the capture change:
    * `Outer := 99` in a nested FUNCTION -- rewritten to the token `Result`,
      which then means that function's OWN result: a type error.
      bug-p-the-enclosing-functions-name-inside-a-nested-function-writes-the-nested-results
    * `Outer.FV := 33` in ANY nested routine -- the enclosing-name rewrite only
      fires when the next token is `:=`, so a qualified write is read as a
      recursive CALL and the program spins until it segfaults.
      bug-p-a-qualified-enclosing-function-name-in-a-nested-routine-recurses

  Oracle: fpc 3.2.2 prints all five rows exactly as below. The pinned compiler
  REFUSES this file ("no overload of PeekIt$.. matches these arguments").
  bug-p-a-sibling-call-to-a-capturing-nested-function-gets-the-wrong-capture-actuals }
{$mode objfpc}{$H+}
type TBox = class FV: LongInt; end;

function Outer: TBox;
var
  top: LongInt;

  { a nested FUNCTION: `Result` is its own, and it is a LongInt }
  function PeekIt: LongInt;
  begin
    if top >= 0 then Result := top else Result := -1;
  end;

  { ...called from a SIBLING, whose own `Result` is a different variable of the
    same type -- this is the call that could not be compiled }
  function PopIt: LongInt;
  begin
    Result := PeekIt;
    Dec(top);
  end;

  { a nested PROCEDURE has no result of its own, so this writes OUTER's }
  procedure SetItFromProc;
  begin
    Result := TBox.Create;
    Result.FV := 11;
  end;

begin
  top := 3;
  SetItFromProc;
  WriteLn('proc set fv=', Result.FV);
  WriteLn('popit=', PopIt);
  WriteLn('top after=', top);
  { and the nested functions' own results did NOT land in the enclosing one }
  WriteLn('fv still=', Result.FV);
end;

var b: TBox;
begin
  b := Outer;
  WriteLn('final fv=', b.FV);
end.
