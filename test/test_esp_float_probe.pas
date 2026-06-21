program test_esp_float_probe;
{ Value-model gating probe for feature-esp-float: exercises Single/Double via
  OPERATORS (a := 1.5; b := a + 2.0; if b > c ...), not by calling the kernels
  directly. The riscv32/xtensa backend lowers these to the soft-float kernels
  (uses softfloat keeps them linked + FindProc-able); the x86-64 oracle computes
  them with native HW float. Both are IEEE-754, so every boolean result must
  match. Output is exact 1/0 lines via the UART (bare) / write syscall (hosted). }

{$ifdef CPU_XTENSA}{$define PXX_ESP}{$endif}
{$ifdef CPU_RISCV32}{$define PXX_ESP}{$endif}

uses softfloat;

{$ifdef PXX_ESP_BARE}
procedure PutC(code: Integer);
begin
  PByte(Int64($60000000))^ := Byte(code);
end;
{$else}
procedure PutC(code: Integer);
var b: Byte; r: Int64;
begin
  b := code;
  r := __pxxrawsyscall(1, 1, Int64(@b), 1);
end;
{$endif}

procedure PutBool(b: Boolean);
begin
  if b then PutC(49) else PutC(48);
  PutC(10);
end;

function DSum(a, b: Double): Double;
begin
  Result := a + b;
end;

function SSum(a, b: Single): Single;
begin
  Result := a + b;
end;

function Mixed(a: Double; b: Single; n: Integer): Double;
begin
  Result := a + b + n;
end;

var
  d, e, f: Double;
  s, t, u: Single;
  i: Integer;
begin
  { Double arithmetic + comparison }
  d := 3.0; e := 4.0; f := d + e;
  PutBool(f = 7.0);             { 1 }
  PutBool(d < e);              { 1 }
  PutBool(d > e);              { 0 }
  PutBool(d <= e);             { 1 }
  PutBool(d >= e);             { 0 }
  PutBool(d <> e);             { 1 }
  f := e - d; PutBool(f = 1.0);    { 1 }
  f := d * e; PutBool(f = 12.0);   { 1 }
  f := e / d; PutBool(f > 1.3);    { 1  (1.333..) }
  PutBool(f < 1.4);           { 1 }

  { Single arithmetic + double-literal store conversion (d2s) }
  s := 1.5; t := 2.5; u := s + t;
  PutBool(u = 4.0);           { 1 (single u promoted to double for the compare) }
  PutBool(s < t);             { 1 }
  u := t - s; PutBool(u = 1.0);   { 1 }
  u := s * t; PutBool(u = 3.75);  { 1 }

  { Integer -> float store conversion (i2d / i2s) }
  i := 5; d := i; PutBool(d = 5.0);   { 1 }
  i := 7; s := i; PutBool(s = 7.0);   { 1 }

  { Mixed int/float in an expression (int operand widened) }
  d := 2.0; PutBool(d + 3 = 5.0);     { 1 }

  { Float params + returns }
  d := DSum(3.0, 4.0);   PutBool(d = 7.0);    { 1 }
  u := SSum(1.5, 2.5);   PutBool(u = 4.0);    { 1 }
  d := Mixed(1.0, 2.5, 3); PutBool(d = 6.5);  { 1 (double + single + int) }

  { Float unary minus (IEEE sign-bit flip, not integer negate) }
  d := 5.0; e := -d; PutBool(e = -5.0);   { 1 }
  s := 2.5; u := -s; PutBool(u = -2.5);   { 1 }
  d := 5.0; PutBool(-d < 0.0);            { 1 }

  { Trunc (float -> int, toward zero) }
  d := 7.9;  i := Trunc(d); PutBool(i = 7);    { 1 }
  d := -3.5; i := Trunc(d); PutBool(i = -3);   { toward zero -> 1 }
  s := 5.8;  i := Trunc(s); PutBool(i = 5);    { 1 }

  { Round (nearest, ties to even — matches SSE cvtsd2si oracle) }
  d := 2.5; i := Round(d); PutBool(i = 2);     { tie -> even -> 1 }
  d := 3.5; i := Round(d); PutBool(i = 4);     { tie -> even -> 1 }
  d := 2.4; i := Round(d); PutBool(i = 2);     { 1 }
  d := -2.6; i := Round(d); PutBool(i = -3);   { 1 }

  { Int (integer part, as float) + Frac (fractional part) }
  d := 3.75; e := Int(d);  PutBool(e = 3.0);   { 1 }
  d := 3.75; e := Frac(d); PutBool(e = 0.75);  { 1 }
  d := -3.75; e := Int(d); PutBool(e = -3.0);  { 1 }
end.
