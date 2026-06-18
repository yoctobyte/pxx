program test_esp_softdiv;
{ Integer div/mod. On xtensa the LX6 software fallback (--xtensa-cpu=lx6 ->
  __pxx_divsi3/__pxx_modsi3) must produce the same results as native quos/rems.
  Covers positive/negative operands. Output digits compared to x86-64 oracle. }
{$ifdef CPU_XTENSA}{$define PXX_ESP}{$endif}
{$ifdef CPU_RISCV32}{$define PXX_ESP}{$endif}
{$ifdef PXX_ESP}
procedure esp_rom_printf(fmt: string; v: Integer); external;
procedure vTaskDelay(ticks: Integer); external;
procedure PutC(code: Integer); begin esp_rom_printf('%c', code); end;
{$else}
procedure PutC(code: Integer); var b: Byte; r: Int64; begin b := code; r := __pxxrawsyscall(1,1,Int64(@b),1); end;
{$endif}
procedure PutInt(n: Integer);
begin
  if n < 0 then begin PutC(45); n := -n; end;
  if n >= 10 then PutInt(n div 10);
  PutC(48 + (n mod 10));
end;
procedure Line(n: Integer); begin PutInt(n); PutC(10); end;
begin
  Line(100 div 7);      { 14 }
  Line(100 mod 7);      { 2 }
  Line(-100 div 7);     { -14 }
  Line(-100 mod 7);     { -2 }
  Line(100 div -7);     { -14 }
  Line(100 mod -7);     { 2 }
  Line(123456 div 789); { 156 }
  Line(123456 mod 789); { 372 }
  Line(5 div 10);       { 0 }
{$ifdef PXX_ESP} while True do vTaskDelay(1000); {$endif}
end.
