{ A PARAMETERLESS function's bare own name read as a value is the one construct
  whose meaning DIFFERS between the reference dialects:

    FPC {$MODE OBJFPC}  -> reads the function's Result   (what pxx does)
    FPC {$MODE DELPHI}  -> emits a RECURSIVE CALL

  measured, both modes, 2026-08-03. So the same line means two different things
  and pxx used to pick one in silence. A recursive-descent author writing the
  obvious `operand := ParseUnary;` gets the uninitialised Result instead of the
  recursion, the AST comes out corrupt, and it surfaces somewhere else entirely.

  The Makefile greps this file's compile output for the warning — it must fire,
  and the program must still BUILD and RUN, since the idiom is legal.
  bug-paramless-self-recursion-silent-result-read }
program test_pascal_self_result_warn;

var
  depth: Integer;

{ paramless: AMBIGUOUS, must warn }
function ParseThing: Integer;
begin
  Inc(depth);
  Result := 5;
  if depth < 3 then
    Result := ParseThing;      { objfpc/pxx: reads Result (5). delphi: recurses. }
end;

{ paramless but written explicitly — both spellings unambiguous, must NOT warn }
function ExplicitResult: Integer;
begin
  Result := 7;
  if Result > 0 then Result := Result + 1;
end;

function ExplicitCall: Integer;
begin
  Inc(depth);
  if depth < 6 then Result := ExplicitCall() else Result := 42;
end;

{ WITH a parameter, a bare own name cannot be a call, so it is unambiguously the
  result variable — must NOT warn even though it is the same spelling }
function WithParam(n: Integer): Integer;
begin
  WithParam := n * 2;
  if WithParam > 100 then WithParam := 100;
end;

begin
  depth := 0;
  writeln(ParseThing);         { 5 — the Result read, not a recursion }
  writeln(depth);              { 1 — proves it did NOT recurse }
  writeln(ExplicitResult);     { 8 }
  depth := 0;
  writeln(ExplicitCall);       { 42 }
  writeln(depth);              { 6 — proves `F()` DID recurse }
  writeln(WithParam(21));      { 42 }
  writeln(WithParam(60));      { 100 }
end.
