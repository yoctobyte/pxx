program test_esp_bare_float;
{ A float on a bare ESP image. Companion to test_esp_bare.pas, same UART/oracle
  shape, covering the one thing that program deliberately has none of: a float.

  bug-a-esp32c3-bare-profile-cannot-find-the-softfloat-repack-helper — the
  ESP-class targets have no FPU, every float op lowers to a __pxx_* kernel in the
  `softfloat` unit, and that unit was never pulled for them. So ANY float in a
  bare program died at codegen with a `compiler error:`. Filed as an esp32c3
  quirk; it was neither esp32c3-specific nor riscv-specific — xtensa needed one
  more operation than the filed repro to show the same wall.

  Every value here is exact in binary and printed as an INTEGER: the point is
  which kernels get linked and called (i2s, s2d, d2s, fmul, fadd, trunc/round),
  not float formatting — which is Track F's, needs textfile, and is not on ESP. }

{$ifdef CPU_XTENSA}{$define PXX_ESP}{$endif}
{$ifdef CPU_RISCV32}{$define PXX_ESP}{$endif}

{$ifdef PXX_ESP_BARE}
procedure PutC(code: Integer);
begin
  PByte(Int64($60000000))^ := Byte(code);
end;
{$else}
{$ifdef PXX_ESP}
procedure esp_rom_printf(fmt: string; v: Integer); external;
procedure PutC(code: Integer);
begin
  esp_rom_printf('%c', code);
end;
{$else}
procedure PutC(code: Integer);
var b: Byte; r: Int64;
begin
  b := code;
  r := __pxxrawsyscall(1, 1, Int64(@b), 1);
end;
{$endif}
{$endif}

procedure PutS(const s: AnsiString);
var i: Integer;
begin
  for i := 1 to Length(s) do PutC(Ord(s[i]));
end;

procedure PutIntRec(n: Integer);
begin
  if n >= 10 then PutIntRec(n div 10);
  PutC(48 + n mod 10);
end;

procedure PutInt(n: Integer);
begin
  if n < 0 then begin PutC(45); n := -n; end;
  PutIntRec(n);
end;

var
  s: Single;
  d: Double;
  i: Integer;

begin
  i := 3;
  s := i;                       { __pxx_i2s }
  s := s * 2.5;                 { single multiply -> 7.5 }
  PutInt(Trunc(s)); PutC(10);            { 7 }
  d := s;                       { __pxx_s2d  -> 7.5 }
  d := d + 0.5;                 { double add -> 8.0 }
  PutInt(Trunc(d * 2)); PutC(10);        { 16 }
  s := d;                       { __pxx_d2s  -> 8.0 }
  PutInt(Round(s * 4)); PutC(10);        { 32 }
  d := i / 4;                   { `/` is real division even on integers -> 0.75 }
  PutInt(Round(d * 100)); PutC(10);      { 75 }
  { NO Int64->float arm here: xtensa cannot lower one at all
    ("target xtensa: Int64-to-float conversion not yet supported"), which is a
    BACKEND gap, not this bug, and is filed as
    bug-a-xtensa-cannot-lower-an-int64-to-float-conversion. Adding a target
    ifdef to route around it here would hide it. }
  PutS('ESP BARE FLOAT OK'); PutC(10);
{$ifdef PXX_ESP} while True do ; {$endif}
end.
