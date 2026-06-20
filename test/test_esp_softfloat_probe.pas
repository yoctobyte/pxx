program test_esp_softfloat_probe;
{ Gating probe for feature-esp-float: do the soft-float kernels (heavy Int64
  math) actually compile + run on riscv32/xtensa? `uses softfloat` makes them
  ordinary calls, so this needs NO codegen change. The SAME kernel source runs
  on the x86-64 oracle and on the ESP QEMU target, so any output mismatch means
  the ESP backend miscompiles the 64-bit ops the kernels rely on. Results are
  chosen to be exact integers and printed via PutInt (UART on bare metal). }

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

procedure PutIntRec(n: Integer);
begin
  if n >= 10 then PutIntRec(n div 10);
  PutC(48 + n mod 10);
end;

procedure PutInt(n: Integer);
begin
  if n < 0 then begin PutC(45); n := -n; end;
  PutIntRec(n);
  PutC(10);
end;

begin
  { double arithmetic (all integer results) }
  PutInt(__pxx_d2i(__pxx_dadd(__pxx_i2d(3), __pxx_i2d(4))));   { 7 }
  PutInt(__pxx_d2i(__pxx_dsub(__pxx_i2d(50), __pxx_i2d(8))));  { 42 }
  PutInt(__pxx_d2i(__pxx_dmul(__pxx_i2d(6), __pxx_i2d(7))));   { 42 }
  PutInt(__pxx_d2i(__pxx_ddiv(__pxx_i2d(84), __pxx_i2d(2))));  { 42 }
  { fractional survives: 3/2=1.5, *2 = 3 }
  PutInt(__pxx_d2i(__pxx_dmul(__pxx_ddiv(__pxx_i2d(3), __pxx_i2d(2)), __pxx_i2d(2)))); { 3 }

  { single arithmetic }
  PutInt(__pxx_s2i(__pxx_sadd(__pxx_i2s(3), __pxx_i2s(4))));   { 7 }
  PutInt(__pxx_s2i(__pxx_smul(__pxx_i2s(6), __pxx_i2s(7))));   { 42 }
  PutInt(__pxx_s2i(__pxx_sdiv(__pxx_i2s(84), __pxx_i2s(2))));  { 42 }

  { repacks }
  PutInt(__pxx_d2i(__pxx_s2d(__pxx_i2s(5))));                  { 5 }
  PutInt(__pxx_s2i(__pxx_d2s(__pxx_i2d(9))));                  { 9 }

  { compares }
  PutInt(__pxx_dcmp(__pxx_i2d(1), __pxx_i2d(2)));             { -1 }
  PutInt(__pxx_dcmp(__pxx_i2d(5), __pxx_i2d(5)));             { 0 }
  PutInt(__pxx_dcmp(__pxx_i2d(9), __pxx_i2d(2)));             { 1 }
  PutInt(__pxx_scmp(__pxx_i2s(2), __pxx_i2s(7)));             { -1 }

{$ifdef PXX_ESP} while True do ; {$endif}
end.
