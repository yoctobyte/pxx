program test_esp_cast;
{ Ord / Chr / Integer() / LongWord() are identity type-puns on the value model;
  this exercises them on ESP (previously rejected as unsupported builtins). }

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

var c: Char;
begin
  c := 'A';
  PutC(Ord(c));              { A }
  PutC(Ord(c) + 1);          { B }
  PutC(Integer('Z'));        { Z }
  PutC(Ord(Chr(33)));        { ! }
  PutC(10);
{$ifdef PXX_ESP}
  while True do
    vTaskDelay(1000);
{$endif}
end.
