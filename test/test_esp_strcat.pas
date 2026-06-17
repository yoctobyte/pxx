program strcat;
{$ifdef CPU_XTENSA}{$define PXX_ESP}{$endif}
{$ifdef CPU_RISCV32}{$define PXX_ESP}{$endif}
{$ifdef PXX_ESP}
procedure esp_rom_printf(fmt: string; v: Integer); external;
procedure vTaskDelay(ticks: Integer); external;
procedure PutC(code: Integer); begin esp_rom_printf('%c', code); end;
{$else}
procedure PutC(code: Integer); var b: Byte; r: Int64; begin b := code; r := __pxxrawsyscall(1,1,Int64(@b),1); end;
{$endif}
procedure PutS(const s: AnsiString);
var i: Integer;
begin
  for i := 1 to Length(s) do PutC(Integer(s[i]));
  PutC(10);
end;
var a, b, c: AnsiString;
begin
  a := 'PXX';
  b := ' rocks';
  c := a + b;
  PutS(c);                 { PXX rocks }
  PutS(a + b + '!');       { PXX rocks! (nested concat) }
  PutC(48 + Length(c)); PutC(10);   { 9 }
{$ifdef PXX_ESP} while True do vTaskDelay(1000); {$endif}
end.
