{ An integer literal argument to an inlined routine is substituted as a literal
  even when another argument has a side effect or the body calls out. Before,
  one impure argument made the inliner capture EVERY argument into a temp, so
  `Sar(x * 7, 11)` lowered its shifts as variable-count shifts (72 bytes each on
  riscv32 against 12 for a constant one). The values must not change: each
  print is one call with one impure argument, so argument order cannot matter,
  and -O0 (no inlining) is the oracle. }
program test_an_inlined_literal_argument_stays_a_literal_beside_an_impure_one;
{$mode objfpc}
var g: Int64 = 5; calls: Integer = 0;

function Sar(x: Int64; n: Integer): Int64; inline;
begin
  if x >= 0 then Result := x shr n else Result := not ((not x) shr n);
end;

function AddB(x: Int64; b: Byte): Int64; inline;
begin
  Result := x + b;
end;

function AddD(x: Int64; d: Double): Double; inline;
begin
  Result := x + d;
end;

function Bump: Int64;
begin
  Inc(calls); g := g * 3 - 7; Result := g;
end;

procedure Note(v: Int64);
begin
  Inc(calls, Integer(v and 1));
end;

{ a body with a call in it: every non-literal argument is still captured }
function Logged(x: Int64; n: Integer): Int64; inline;
begin
  Note(x);
  Result := x shl n;
end;

var v: Int64; k: Integer;
begin
  v := -123456789;
  writeln(Sar(v * 7, 11));
  writeln(Sar(Bump - 1000, 3));
  writeln(Sar(Bump, 0));
  writeln(Sar(-Bump, 63));
  writeln(Sar(-Bump, 33));
  writeln(AddB(Bump, 255));
  writeln(AddD(Bump, 3):0:1);
  writeln(AddD(Bump, -2):0:1);
  writeln(Logged(Bump, 5));
  writeln(Logged(v * 3, 40));
  for k := 1 to 3 do writeln(Sar(v * k, 7), ' ', Logged(Bump, 1));
  { every argument pure: the old path substituted the int into the Double param too }
  writeln(AddD(v, 3):0:1, ' ', AddD(1097, 3):0:1);
  writeln('calls=', calls, ' g=', g);
end.
