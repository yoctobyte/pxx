program test_esp_iram;
{ `iram;` directive: the routine's machine code is emitted into the ELF
  .iram1.text section (the IDF linker script routes it to internal IRAM). The
  call from app_main (flash .text) to FastPath (.iram1.text) crosses sections,
  so it is lowered to an indirect literal-slot call relocated against FastPath's
  own symbol. On non-ESP targets `iram;` is an accepted no-op, so this same
  source builds as the x86-64 oracle. }
{$ifdef CPU_XTENSA}{$define PXX_ESP}{$endif}
{$ifdef CPU_RISCV32}{$define PXX_ESP}{$endif}
{$ifdef PXX_ESP}
procedure esp_rom_printf(fmt: string; v: Integer); external;
procedure vTaskDelay(ticks: Integer); external;
procedure PutC(code: Integer); begin esp_rom_printf('%c', code); end;
{$else}
procedure PutC(code: Integer); var b: Byte; r: Int64; begin b := code; r := __pxxrawsyscall(1,1,Int64(@b),1); end;
{$endif}
procedure FastPath(n: Integer); iram;
var i: Integer;
begin
  for i := 0 to n - 1 do PutC(65 + i);   { A B C ... }
  PutC(10);
end;
begin
  PutC(83); PutC(10);     { S }
  FastPath(3);            { ABC  (flash -> iram cross-section call) }
  FastPath(5);            { ABCDE }
  PutC(69); PutC(10);     { E }
{$ifdef PXX_ESP} while True do vTaskDelay(1000); {$endif}
end.
