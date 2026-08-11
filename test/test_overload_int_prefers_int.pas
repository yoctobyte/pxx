program TestOverloadIntPrefersInt;
{ Regression for bug-a-an-integer-binop-argument-binds-a-double-overload.

  FPC's rule, measured against fpc 3.2.2: an INTEGER-valued argument prefers an
  INTEGER parameter over a FLOAT one, and it holds even when the integer
  parameter NARROWS — `Fa(Integer)` vs `Fa(Double)` takes Integer for an Int64
  argument, `Fb(Byte)` vs `Fb(Double)` takes Byte for an Integer argument.

  pxx ranked purely by losslessness, so a float parameter (which never
  "narrows" an integer) won whenever the integer one would truncate: `Fa(n + 1)`
  — n an Integer, so the sum is Int64 in FPC too — computed the Double overload
  and answered something entirely different, silently.

  Losslessness still ranks WITHIN the integer candidates, which is the half that
  was already right: Fc below keeps binding Int64 rather than Integer. }

function Fa(x: Integer): string; overload; begin Fa := 'int'; end;
function Fa(x: Double): string;  overload; begin Fa := 'dbl'; end;
function Fb(x: Byte): string;    overload; begin Fb := 'byte'; end;
function Fb(x: Double): string;  overload; begin Fb := 'dbl'; end;
function Fc(x: Int64): string;   overload; begin Fc := 'i64'; end;
function Fc(x: Double): string;  overload; begin Fc := 'dbl'; end;
{ the integer-vs-integer ranking this must not disturb }
function Fd(x: Integer): string; overload; begin Fd := 'int'; end;
function Fd(x: Int64): string;   overload; begin Fd := 'i64'; end;

var n: Integer; q: Int64; y: Byte;
begin
  n := 5; q := 9; y := 2;
  WriteLn('Fa ', Fa(n), ' ', Fa(n + 1), ' ', Fa(q), ' ', Fa(y), ' ', Fa(7), ' ', Fa(2.5));
  WriteLn('Fb ', Fb(n), ' ', Fb(y), ' ', Fb(y + 1), ' ', Fb(7));
  WriteLn('Fc ', Fc(n), ' ', Fc(n + 1), ' ', Fc(q), ' ', Fc(7));
  WriteLn('Fd ', Fd(n), ' ', Fd(n + 1), ' ', Fd(q), ' ', Fd(y), ' ', Fd(7));
  WriteLn('OVERLOAD INT PREFERS INT OK');
end.
