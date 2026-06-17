program test_esp_hello;
{ Div-free portable smoke: emits a fixed byte sequence through the per-target
  PutC primitive. Runs on both esp ISAs today (no div/mod/heap), so it is the
  first cross-checkable ESP feature test -- the esp32s3 (xtensa) / esp32c3
  (riscv32) qemu serial must match the x86-64 oracle byte for byte.
  test_esp_print adds integer formatting once xtensa div/mod lands. }

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
  r := __pxxrawsyscall(1, 1, Int64(@b), 1);   { SYS_write, fd=1 (x86-64 numbering) }
end;
{$endif}

begin
  PutC(80); PutC(88); PutC(88); PutC(10);   { "PXX\n" }
  PutC(79); PutC(75); PutC(10);             { "OK\n"  }
{$ifdef PXX_ESP}
  { app_main has no returning epilogue on esp yet; park so the FreeRTOS idle
    task keeps feeding the watchdog while qemu is captured. }
  while True do
    vTaskDelay(1000);
{$endif}
end.
