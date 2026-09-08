{ The delphi half of test_nested_bare_enclosing_name_objfpc.pas, and it asserts
  the OPPOSITE answer on purpose.

  In `$mode delphi` the enclosing function's bare parameterless name, read from
  inside a nested routine, is a RECURSIVE CALL -- not the result variable. That
  is what fpc 3.2.2 does and what pxx already did, so nothing here is a fix.

  THIS FILE EXISTS BECAUSE THE CELL THAT WAS RIGHT HAD NO ASSERTION BEHIND IT.
  The ticket reporting the objfpc defect measured objfpc only and described a
  flat divergence from fpc, which invites exactly one repair: rewrite the bare
  name unconditionally. That repair is correct in objfpc and silently wrong
  here, and no in-tree row would have caught it -- the one control the ticket
  named is parenthesised, so it never exercises the bare spelling at all.

  The counter is the assertion. A result read and a recursive call return the
  same 40 in this shape; only `calls` tells them apart -- 2 here, 1 in the
  objfpc file. Value-only rows pass under both readings.
  bug-p-a-bare-enclosing-function-name-read-in-a-nested-routine-recurses }
{$mode delphi}{$H+}
program test_nested_bare_enclosing_name_delphi;
type
  TBox = class FV: LongInt; end;
var
  calls, depth, lastT: LongInt;

{ 1. bare read from a nested function: a CALL, so calls=2. }
function F: LongInt;
var t: LongInt;
  function Inner: LongInt;
  begin
    if depth = 0 then begin Inc(depth); Inner := F; end else Inner := -1;
  end;
begin
  Inc(calls);
  Result := 40;
  t := Inner;
  lastT := t;
end;

{ 2. `Result` from a nested PROCEDURE is still the enclosing result in delphi --
     the capture path is not mode-dependent and must not become so. }
function R: LongInt;
  procedure Inner;
  begin
    Result := 77;
  end;
begin
  Inc(calls);
  Result := 1;
  Inner;
end;

{ 3. a QUALIFIED enclosing name is the result variable in BOTH modes -- fpc
     3.2.2 measured, calls=1 either way. This row is why the bare-read arm is
     keyed on the mode and the selector arm is not. }
function Q: TBox;
  procedure P;
  begin
    Q.FV := 33;
  end;
begin
  Inc(calls);
  Result := TBox.Create;
  Result.FV := 1;
  P;
end;

begin
  calls := 0; depth := 0; lastT := 0;
  WriteLn('F=', F, ' calls=', calls, ' lastT=', lastT);
  calls := 0;
  WriteLn('R=', R, ' calls=', calls);
  calls := 0;
  WriteLn('Q=', Q.FV, ' calls=', calls);
end.
