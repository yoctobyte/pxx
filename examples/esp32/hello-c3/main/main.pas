program Esp32Hello;
{ Minimal PXX -> ESP-IDF integration proof (feature-esp32-idf-riscv32).
  Compiled with `--target=riscv32` to a relocatable main.o whose exported
  app_main is called by ESP-IDF's startup task. The two externals resolve at
  IDF link time: esp_rom_printf works before full console init, vTaskDelay
  yields to FreeRTOS so the watchdog stays happy between lines. }

procedure esp_rom_printf(fmt: string; v: Integer); external;
procedure vTaskDelay(ticks: Integer); external;

var
  i, acc: Integer;
begin
  acc := 0;
  i := 1;
  while i <= 5 do
  begin
    acc := acc + i;
    esp_rom_printf('PXX hello from Pascal: i=%d'#10, i);
    vTaskDelay(10);
    i := i + 1;
  end;
  esp_rom_printf('PXX sum 1..5 = %d'#10, acc);
  { app_main has no returning epilogue yet (bare-metal self-loop); park
    politely so the FreeRTOS idle task keeps running and feeds the WDT. }
  while True do
    vTaskDelay(1000);
end.
