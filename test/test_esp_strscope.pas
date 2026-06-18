program test_esp_strscope;
{ ARC scope-exit DecRef of local managed strings. Churn builds a local string
  and returns; without scope-exit DecRef the 64KB static arena leaks ~48 bytes
  per call and overflows well before 4000 iterations. MakeStr keeps its Result
  while still releasing an unrelated local. Output: arena survives + "OK4". }
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
procedure Churn;
var s: AnsiString;
begin
  s := 'churn-string-payload-data';   { local -> DecRef at scope exit }
end;
function MakeStr: AnsiString;
var local: AnsiString;
begin
  local := 'discard';                 { local -> DecRef at scope exit }
  Result := 'kept';                   { returned -> NOT released }
end;
var i: Integer; r: AnsiString;
begin
  for i := 1 to 4000 do Churn;        { arena must survive }
  r := MakeStr;
  PutC(79); PutC(75);                 { OK }
  PutC(48 + Length(r));               { 4 }
  PutC(10);
  PutS(r);                            { kept }
{$ifdef PXX_ESP} while True do vTaskDelay(1000); {$endif}
end.
