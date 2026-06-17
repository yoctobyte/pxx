program test_esp_print;
{ Heap-free portable Print: shared recursive integer formatting over a
  per-target PutC primitive. x86-64/Linux writes fd 1 via the __pxxrawsyscall
  intrinsic; esp riscv32 writes the ROM console via esp_rom_printf. The byte
  stream is identical, so the x86-64 run is the oracle for the esp32-c3 qemu
  run. No heap, no dynarray, no array-of-const, no Ord/Chr builtin calls --
  runs on the riscv32 stage-1 subset, the bootstrap output path for the ESP
  harness. PutC takes a raw ASCII code so no Char/Ord/Chr lowering is needed. }

{$ifdef CPU_RISCV32}
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

procedure NewLine;
begin
  PutC(10);
end;

procedure PrintIntRec(n: Integer);
begin
  if n >= 10 then PrintIntRec(n div 10);
  PutC(48 + n mod 10);   { '0' = 48 }
end;

procedure PrintInt(n: Integer);
begin
  if n < 0 then
  begin
    PutC(45);            { '-' = 45 }
    n := -n;
  end;
  PrintIntRec(n);
end;

procedure PrintLnInt(n: Integer);
begin
  PrintInt(n);
  NewLine;
end;

var
  i, sum: Integer;
begin
  sum := 0;
  for i := 1 to 5 do
  begin
    PrintLnInt(i);
    sum := sum + i;
  end;
  PrintLnInt(sum);
{$ifdef CPU_RISCV32}
  { app_main has no returning epilogue on esp yet; park politely so the
    FreeRTOS idle task keeps feeding the watchdog while qemu is captured. }
  while True do
    vTaskDelay(1000);
{$endif}
end.
