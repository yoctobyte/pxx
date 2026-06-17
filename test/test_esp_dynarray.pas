program test_esp_dynarray;
{ ESP dynamic array smoke: SetLength over the static-arena allocator, element
  store/index, and Length (header at [handle-8]). Output must match the x86-64
  oracle (real allocator). Unmanaged elements only (managed-element retain is
  deferred on ESP). }

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

var
  a: array of Integer;
  i, sum: Integer;
begin
  SetLength(a, 5);
  for i := 0 to 4 do
    a[i] := (i + 1) * 10;
  PrintLnInt(Length(a));        { 5 }
  sum := 0;
  for i := 0 to Length(a) - 1 do
    sum := sum + a[i];
  PrintLnInt(sum);              { 150 }
  SetLength(a, 2);              { shrink; keeps a[0], a[1] }
  PrintLnInt(Length(a));        { 2 }
  PrintLnInt(a[0] + a[1]);      { 30 }
{$ifdef PXX_ESP}
  while True do
    vTaskDelay(1000);
{$endif}
end.
