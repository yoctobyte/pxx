{ SPDX-License-Identifier: Zlib }
unit mimic_esp32;
{$MODE PXX}   { our dialect; the FPC-parity strict-* flags do not judge this file }
{ MicroPython's `esp32` module, the one call a status page wants:

      import esp32
      print(esp32.mcu_temperature())    # e.g. 41

  mcu_temperature() is the chip's internal sensor in whole degrees Celsius,
  an int as in MicroPython (S2, S3, C3 and later; the classic ESP32 has no
  such sensor and raises OSError, where MicroPython has raw_temperature()).
  It reads the die, not the room: expect it well above ambient, and rising
  with Wi-Fi traffic.

  Only for an ESP build (the file lives in lib/rtl/platform/esp). The C half
  is lib/rtl/platform/esp/idf/pxx_esp, because the sensor's default clock is a
  different enum on each chip and IDF's TEMPERATURE_SENSOR_CONFIG_DEFAULT is
  the one place that knows it. }

interface

uses pylib, sysutils;

function mcu_temperature: Integer;

implementation

function pxx_mcu_temperature(celsius: Pointer): Integer; external;

function mcu_temperature: Integer;
var c: Single; rc: Integer;
begin
  c := 0;
  rc := pxx_mcu_temperature(@c);
  if rc <> 0 then
    raise OSError.Create('esp32.mcu_temperature: the sensor answered esp_err_t 0x' + IntToHex(rc, 3));
  mcu_temperature := Round(c);
end;

end.
