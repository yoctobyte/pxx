program test_user_type_shadows_builtin;

{ bug-procedure-typed-procvalue (real root cause): a user `type X = ...` alias
  must SHADOW a same-named builtin descriptor record. PXX exposes internal
  records (TProc, TParam, ...) under common names; a user program declaring
  `type TProc = procedure(...)` previously resolved to the builtin record, so the
  proc-typed var lost its signature and the indirect call `p(...)` failed with
  "unexpected token". The fix prefers the user alias over the builtin record. }

type
  TProc = procedure(x: Integer);          { collides with builtin REC_TPROC }
  TFn   = function(x: Integer): Integer;

var
  pp: TProc;
  pf: TFn;

procedure Show(x: Integer);
begin
  WriteLn('show ', x);
end;

function Dbl(x: Integer): Integer;
begin
  Dbl := x * 2;
end;

begin
  pp := @Show;
  pp(7);                  { show 7 }
  pf := @Dbl;
  WriteLn('dbl=', pf(5)); { dbl=10 }
end.
