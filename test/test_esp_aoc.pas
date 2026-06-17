program test_esp_aoc;
{ The payoff of the ESP managed arc: a portable writeln built on `array of
  const`. WriteVals takes a TVarRec open array, dispatches on VType, and prints
  each element through the per-target PutC. Integers only for now (managed
  strings are a later ESP step). Output must match the x86-64 oracle, which
  runs the same code over the real allocator. }

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

procedure PrintInt(n: Integer);
begin
  if n < 0 then begin PutC(45); n := -n; end;
  PrintIntRec(n);
end;

procedure WriteVals(const items: array of const);
var i: Integer;
begin
  for i := 0 to Length(items) - 1 do
  begin
    if i > 0 then PutC(32);            { space separator }
    if items[i].VType = 0 then         { vtInteger }
      PrintInt(items[i].VInteger);
  end;
  PutC(10);
end;

begin
  WriteVals([1, 2, 3]);
  WriteVals([42, -7, 100, 999]);
{$ifdef PXX_ESP}
  while True do
    vTaskDelay(1000);
{$endif}
end.
