{ The {$MODE DELPHI} half of the bare-own-name rule. Sibling of
  test_pascal_self_result_warn.pas, which covers the objfpc/default half.

  A PARAMETERLESS function's bare own name read as a value is the one construct
  where the reference dialects disagree, and pxx follows whichever mode is set:

    default / {$MODE OBJFPC}  -> reads the function's Result   (no recursion)
    {$MODE DELPHI}            -> a RECURSIVE CALL

  Both measured against FPC 3.2.2 in the corresponding mode, 2026-08-03.

  This behaviour lives in the same ParseFactor branch as the --warn-self-result
  diagnostic (guarded by `not DelphiMode`), so it is exactly what a change to
  that warning could silently break — and until now nothing pinned it.

  The warning must also stay SILENT here: in delphi mode the construct is
  unambiguous, and the warning's text ("reads the result") would be false.
  bug-paramless-self-recursion-silent-result-read }
program test_pascal_self_result_delphi;
{$MODE DELPHI}

var
  depth: Integer;

{ paramless: in delphi mode the bare own name RECURSES }
function CountDown: Integer;
begin
  Inc(depth);
  if depth < 4 then
    Result := CountDown        { a recursive call here, NOT a Result read }
  else
    Result := 42;
end;

{ explicit forms mean the same thing in every mode }
function ExplicitCall: Integer;
begin
  Inc(depth);
  if depth < 3 then Result := ExplicitCall() else Result := 7;
end;

function ExplicitResult: Integer;
begin
  Result := 5;
  Result := Result * 2;
end;

begin
  depth := 0;
  writeln(CountDown);          { 42 — the recursion reached the base case }
  writeln(depth);              { 4  — proves it DID recurse (objfpc gives 1) }

  depth := 0;
  writeln(ExplicitCall);       { 7 }
  writeln(depth);              { 3 }

  writeln(ExplicitResult);     { 10 }
end.
