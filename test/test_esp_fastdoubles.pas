program test_esp_fastdoubles;
{ {$FASTDOUBLES ON}: on xtensa with --xtensa-fpu, Double +,-,* are computed
  through the hardware single FPU (d2s -> op.s -> s2d) instead of the soft-double
  kernels — lossy single precision, traded for speed. This probe uses only
  integer-valued doubles, which are EXACT in single precision, so the fast path
  produces the same bits as a true double — letting it diff against the x86-64
  oracle (where the directive is a no-op and native doubles are used). Fractional
  results would diverge by design and are NOT checked here. Run the ESP side with
  ESP_PXXFLAGS=--xtensa-fpu. }
{$FASTDOUBLES ON}
{$ifdef CPU_XTENSA}{$define PXX_ESP}{$endif}
{$ifdef CPU_RISCV32}{$define PXX_ESP}{$endif}

uses softfloat;   { d2s/s2d repacks (fast path) + soft-double kernels (fallback) }

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

var
  d, e, f: Double;
begin
  d := 100.0; e := 7.0;
  f := d + e; PutBool(f = 107.0);   { 1 }
  f := d - e; PutBool(f = 93.0);    { 1 }
  f := d * e; PutBool(f = 700.0);   { 1 }
  f := (d + e) * 2.0; PutBool(f = 214.0);  { 1 }
  f := d * e - e; PutBool(f = 693.0);      { 1 }
end.
