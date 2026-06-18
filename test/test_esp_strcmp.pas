program test_esp_strcmp;
{$ifdef CPU_XTENSA}{$define PXX_ESP}{$endif}
{$ifdef CPU_RISCV32}{$define PXX_ESP}{$endif}
{$ifdef PXX_ESP}
procedure esp_rom_printf(fmt: string; v: Integer); external;
procedure vTaskDelay(ticks: Integer); external;
procedure PutC(code: Integer); begin esp_rom_printf('%c', code); end;
{$else}
procedure PutC(code: Integer); var b: Byte; r: Int64; begin b := code; r := __pxxrawsyscall(1,1,Int64(@b),1); end;
{$endif}
procedure PutB(x: Boolean); begin if x then PutC(89) else PutC(78); PutC(10); end;  { Y/N }
var a, b: AnsiString;
begin
  a := 'foo';
  b := 'foo';
  PutB(a = b);          { Y (var=var) }
  PutB(a = 'bar');      { N (var=literal) }
  PutB(a <> 'bar');     { Y }
  PutB(a = 'foo');      { Y (var=matching literal) }
  PutB(b <> a);         { N }
{$ifdef PXX_ESP} while True do vTaskDelay(1000); {$endif}
end.
