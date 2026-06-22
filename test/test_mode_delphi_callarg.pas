{$mode delphi}
program test_mode_delphi_callarg;

{ mode delphi -- @-optional procedural value at the CALL-ARGUMENT bind site.
  Passing a bare routine name as an argument to a proc-typed parameter takes its
  address (no @), the same delta already supported at the assignment site. Three
  shapes:
    1. with-params function name        -> proc-value (unambiguous: can't call
                                           it without args here).
    2. parameterless procedure name     -> proc-value (a procedure call yields no
                                           value, so the bare name is the address).
    3. paramless FUNCTION name          -> call-first precedence: a real call is
                                           tried first; @F is only the fallback
                                           when the call result doesn't fit. So a
                                           paramless function passed to a proc-
                                           typed parameter still takes its address
                                           (the call result -- Integer -- does not
                                           fit a procedural parameter).
  FPC -Mdelphi is the oracle for all three. }

type
  TFn  = function(x: Integer): Integer;
  TNul = function: Integer;
  TPrc = procedure;

var
  log: Integer;

function Dbl(x: Integer): Integer;
begin Result := x * 2; end;

function Seven: Integer;
begin Result := 7; end;

procedure Bump;
begin log := log + 10; end;

function ApplyFn(f: TFn; v: Integer): Integer;
begin Result := f(v); end;

function CallNul(f: TNul): Integer;
begin Result := f() + f(); end;

procedure RunPrc(p: TPrc);
begin p(); p(); end;

begin
  log := 0;

  { 1. with-params function name as proc-value arg }
  WriteLn('ApplyFn=', ApplyFn(Dbl, 21));       { 42 }

  { 2. paramless procedure name as proc-value arg (statement-call path) }
  RunPrc(Bump);
  WriteLn('log=', log);                         { 20 }

  { 3. paramless function name -> address (fallback; result Integer != TNul) }
  WriteLn('CallNul=', CallNul(Seven));          { 14 }
end.
