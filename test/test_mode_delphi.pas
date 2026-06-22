{$mode delphi}
program test_mode_delphi;

{ mode delphi -- PXX honours the two behavioural deltas vs its objfpc-ish
  default (both FPC -Mdelphi-verified):
  1. at-optional procedural value: p := Fn (no at-sign) binds the function's
     address to a proc-typed target.
  2. A bare PARAMLESS own-name inside a function body is a recursive CALL (in
     objfpc/default it is the result variable -- the project flip). With
     parameters a bare name stays the result var in both modes. }

type TFn = function(x: Integer): Integer;

var p: TFn;
    calls: Integer;

function Dbl(x: Integer): Integer;
begin
  Dbl := x * 2;            { with params: bare Dbl on LHS = result write, both modes }
end;

function Gate: Integer;     { paramless: bare Gate read = recursive CALL in delphi }
begin
  calls := calls + 1;
  if calls < 3 then Gate := Gate   { recurses (delphi); would be result var in objfpc }
  else Gate := 42;
end;

function Tally(n: Integer): Integer;
begin
  Result := n;
  Result := Result + 100;   { delphi reads the result via Result, not the name }
end;

begin
  p := Dbl;                 { delphi: no @ needed }
  WriteLn('p5=', p(5));     { 10 }

  calls := 0;
  WriteLn('Gate=', Gate, ' calls=', calls);   { 42 3 (recursed) }

  WriteLn('Tally=', Tally(5));                 { 105 }
end.
