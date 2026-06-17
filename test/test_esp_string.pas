program test_esp_string;
{ Managed AnsiString (PXX default): literal build via PXXStrFromLit, Length
  [handle-8], char index handle+(i-1). Prints chars via PutC; matches the
  x86-64 oracle. }
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
var s, t: AnsiString;
begin
  s := 'PXX';
  PutC(48 + Length(s)); PutC(10);   { 3 }
  PutS(s);                          { PXX }
  t := s;                           { copy (refcount) }
  PutS(t);                          { PXX }
{$ifdef PXX_ESP} while True do vTaskDelay(1000); {$endif}
end.
