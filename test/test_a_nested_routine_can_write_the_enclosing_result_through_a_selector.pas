program test_a_nested_routine_can_write_the_enclosing_result_through_a_selector;
{ `Outer.FV := 33` FROM A NESTED ROUTINE COMPILED TO A RECURSIVE CALL TO Outer:
  no diagnostic, unbounded recursion, SIGSEGV. `Result.FV := 33` in the same
  position worked, and so did a bare `Outer := ...`. It was the COMBINATION --
  the enclosing NAME, then a selector -- that had no path.

  ParseNestedRoutine's enclosing-name rewrite fires only where the very next
  token is `:=`. That test is correct for a BARE name, where the other reading
  really is a recursive call, and it answers NO for every qualified one.

  A SELECTOR IS ENOUGH ON ITS OWN, AND THE CAUTIOUS RULE IS THE WRONG ONE. The
  careful-looking fix is "walk the selector chain and rewrite only if it ends at
  `:=`", reasoning that a qualified name on the RIGHT must be a call. Rows `rmw`
  and `read` are here because fpc 3.2.2 says otherwise and I had written the
  cautious version before measuring:

    rmw   `Outer.FV := Outer.FV + 6` from 60 gives 66. Under the cautious rule
          the RIGHT-hand `Outer.FV` stays a call and the program never returns.
    read  a nested `gRead := Outer.FV`, entered once behind a depth counter, is
          the CURRENT result (70) and not a re-entry (which would be 71). The
          two values differ ON PURPOSE: with both at 70 the row could not tell a
          call from a read, which is the collision that makes a guard unable to
          fail.

  So under fpc the function's name CARRYING A SELECTOR is the result variable in
  either position, and only a bare name has the two readings the `:=` test
  exists to separate. `(` is deliberately not in the set, so `Outer(x).F` stays
  a call.

  NESTED PROCEDURE ONLY, AND THE LIMIT IS THE OTHER TICKET RATHER THAN CAUTION.
  The rewrite's target is the token `Result`, which inside a nested FUNCTION
  names THAT function's result. Widening this to a nested function would swap an
  unbounded recursion for a SILENT write to the wrong variable -- strictly
  worse -- so a nested function keeps today's behaviour until the enclosing
  result has a distinct spelling. THAT ROW IS DELIBERATELY NOT ASSERTED HERE:
  it still recurses and cannot be run, and asserting a crash is not an
  assertion.
  [[bug-p-the-enclosing-functions-name-inside-a-nested-function-writes-the-nested-results]]

  Rows `dot`, `brack` and `caret` are the three selectors; `bare` is the control
  that the pre-existing `:=` spelling is untouched. The bare name's OTHER
  reading -- a genuine recursive call -- is asserted in
  test_a_nested_routine_assigns_the_enclosing_functions_result.pas, which stays
  green.

  All rows measured against fpc 3.2.2.
  bug-p-a-qualified-enclosing-function-name-in-a-nested-routine-recurses }
{$mode objfpc}{$H+}
type
  TBox = class FV: LongInt; end;
  TArr = array[0..2] of LongInt;
  PInt = ^LongInt;
var depth, gRead: LongInt;

function F1: TBox;
  procedure P; begin F1.FV := 33; end;
begin Result := TBox.Create; Result.FV := 1; P; end;

function F2: TArr;
  procedure P; begin F2[1] := 44; end;
begin Result[1] := 2; P; end;

function F3: PInt;
  procedure P; begin F3^ := 55; end;
begin New(Result); Result^ := 3; P; end;

function F4: TBox;
  procedure P; begin F4.FV := F4.FV + 6; end;
begin Result := TBox.Create; Result.FV := 60; P; end;

function F5: TBox;
  procedure P;
  begin
    if depth = 0 then begin Inc(depth); gRead := F5.FV; end;
  end;
begin Result := TBox.Create; Result.FV := 70 + depth; P; end;

function F6: LongInt;
  procedure P; begin F6 := 88; end;
begin Result := 8; P; end;

var b: TBox; a: TArr; q: PInt;
begin
  b := F1;      WriteLn('dot   = ', b.FV);
  a := F2;      WriteLn('brack = ', a[1]);
  q := F3;      WriteLn('caret = ', q^);
  b := F4;      WriteLn('rmw   = ', b.FV);
  depth := 0; gRead := -1;
  b := F5;      WriteLn('read  = ', gRead, ' ', b.FV);
  WriteLn('bare  = ', F6);
end.
