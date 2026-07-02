{ SPDX-License-Identifier: 0BSD }
program Esp32S3Hello;
{ Minimal PXX -> ESP-IDF Xtensa integration proof.
  Compiled with `--target=xtensa --xtensa-abi=windowed` to a relocatable
  main.o whose exported app_main is called by ESP-IDF's startup task. }

procedure esp_rom_printf(fmt: string; v: Integer); external;
procedure gpio_set_direction(gpio_num: Integer; mode: Integer); external;
procedure gpio_set_level(gpio_num: Integer; level: Integer); external;
procedure vTaskDelay(ticks: Integer); external;

var
  i, acc, led: Integer;
begin
  acc := 0;
  led := 0;
  gpio_set_direction(2, 2);
  i := 1;
  while i <= 5 do
  begin
    acc := acc + i;
    led := 1 - led;
    gpio_set_level(2, led);
    esp_rom_printf('PXX hello from Pascal S3: i=%d'#10, i);
    vTaskDelay(100);
    i := i + 1;
  end;
  esp_rom_printf('PXX S3 sum 1..5 = %d'#10, acc);
  while True do
  begin
    gpio_set_level(2, 1);
    vTaskDelay(500);
    gpio_set_level(2, 0);
    vTaskDelay(500);
  end;
end.
