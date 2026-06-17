program test_esp_heap;
{ ESP heap smoke: New/GetMem over the static arena (ESP) vs mmap (x86-64).
  Allocates several blocks, proves they are distinct + writable, and prints
  values + a sum through the per-target PutC. Output must match the x86-64
  oracle (which uses the real allocator), validating the static-arena port. }

{$ifdef CPU_XTENSA}{$define PXX_ESP}{$endif}
{$ifdef CPU_RISCV32}{$define PXX_ESP}{$endif}

{$ifdef PXX_ESP}
procedure esp_rom_printf(fmt: string; v: Integer); external;
procedure vTaskDelay(ticks: Integer); external;
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

procedure PrintIntRec(n: Integer);
begin
  if n >= 10 then PrintIntRec(n div 10);
  PutC(48 + n mod 10);
end;

procedure PrintLnInt(n: Integer);
begin
  if n < 0 then begin PutC(45); n := -n; end;
  PrintIntRec(n);
  PutC(10);
end;

type
  PInt = ^Integer;

var
  a, b, c: PInt;
  sum: Integer;
begin
  New(a);
  New(b);
  New(c);
  a^ := 100;
  b^ := 20;
  c^ := 3;
  { distinct blocks: writing c must not disturb a/b }
  PrintLnInt(a^);
  PrintLnInt(b^);
  PrintLnInt(c^);
  sum := a^ + b^ + c^;
  PrintLnInt(sum);
  Dispose(a);
  Dispose(b);
  Dispose(c);
{$ifdef PXX_ESP}
  while True do
    vTaskDelay(1000);
{$endif}
end.
