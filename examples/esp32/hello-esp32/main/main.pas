{ SPDX-License-Identifier: 0BSD }
program Esp32Hello;
{ Minimal PXX -> ESP-IDF integration proof for the CLASSIC ESP32 (Xtensa LX6).

  DELIBERATELY THE SAME PROGRAM AS hello-s3/main/main.pas, down to the GPIO pin
  and the loop bounds, with only the printed words changed. The question this
  project exists to answer is whether pxx's xtensa codegen runs on LX6 as it
  does on the S3's LX7, and holding the program axis fixed is what makes a
  difference attributable to the chip. If you change this program, the
  comparison with hello-s3 stops being a comparison.

  Compiled with `--target=esp32`, which on the IDF platform implies the
  windowed ABI (ESP-IDF enters app_main with CALLX8 and expects RETW). }

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
    esp_rom_printf('PXX hello from Pascal ESP32: i=%d'#10, i);
    vTaskDelay(100);
    i := i + 1;
  end;
  esp_rom_printf('PXX ESP32 sum 1..5 = %d'#10, acc);
  while True do
  begin
    gpio_set_level(2, 1);
    vTaskDelay(500);
    gpio_set_level(2, 0);
    vTaskDelay(500);
  end;
end.
