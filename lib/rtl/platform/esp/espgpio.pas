{ SPDX-License-Identifier: Zlib }
unit espgpio;
{$MODE PXX}   { our dialect; the FPC-parity strict-* flags do not judge this file }
{ ESP32 GPIO: the output path, for Pascal and for Nil Python.

  NO gpio_config HERE, AND THAT IS THE POINT. `gpio_config_t` is a struct whose
  LAYOUT IS PER CHIP -- its last field `hys_ctrl_mode` is compiled in only when
  SOC_GPIO_SUPPORT_PIN_HYS_FILTER is defined, which is true for esp32c5, c61,
  h2, h21 and p4 and false for esp32c3 and esp32s3 (measured against this
  IDF's soc_caps.h, 2026-09-19). A Pascal mirror of it is therefore right for
  some chips and short for others, and a short struct hands the SDK garbage in
  a field it reads. `examples/esp32/gpio-c3/main/main.pas` mirrors it because
  it is a PROBE of the interrupt path and needs intr_type; nothing here does.
  gpio_reset_pin + gpio_set_direction + gpio_set_level take plain ints and are
  the same call on every chip.

  WHAT QEMU DOES AND DOES NOT MODEL, measured 2026-08-30 and unchanged: the
  INPUT path is not modelled at all -- a pin configured input with a pull-up
  reads 0 where silicon reads 1, and edge interrupts never fire
  (feature-esp-gpio-and-adc-callback-slices, blocked on hardware). So
  gpio_read is here for silicon and CANNOT be asserted under emulation, and
  the writes below EXECUTE under qemu (rc=0) while their effect is
  unobservable there. Do not write a test that claims otherwise; do not
  "verify" this unit by reading back what you wrote.

  IDF-only: these resolve at IDF link time and nothing here works on a bare
  boot. The component is esp_driver_gpio -- a project using this unit needs it
  in its REQUIRES. }

interface

const
  { gpio_mode_t, from hal/gpio_types.h: BIT0 input, BIT1 output, BIT2 open-drain }
  GPIO_MODE_DISABLE      = 0;
  GPIO_MODE_INPUT        = 1;
  GPIO_MODE_OUTPUT       = 2;
  GPIO_MODE_INPUT_OUTPUT = 3;

{ Pascal surface. Each returns the SDK's esp_err_t; 0 is ESP_OK. }
function GpioReset(pin: Integer): Integer;
function GpioSetDirection(pin, mode: Integer): Integer;
function GpioSetLevel(pin, level: Integer): Integer;
function GpioGetLevel(pin: Integer): Integer;

{ ---- the Nil Python surface ----------------------------------------------
  Plain ints in and out, so it crosses the seam with no marshalling question:

      import 'espgpio.pas' as gpio
      gpio.gpio_output(8)          # reset the pin and drive it
      gpio.gpio_write(8, 1)

  gpio_read is the one that emulation cannot answer; see the header. }
function gpio_output(pin: Integer): Integer;
function gpio_write(pin, level: Integer): Integer;
function gpio_read(pin: Integer): Integer;

implementation

{ components/esp_driver_gpio. All resolve at IDF link time. }
function gpio_reset_pin(pin: Integer): Integer; external;
function gpio_set_direction(pin, mode: Integer): Integer; external;
function gpio_set_level(pin, level: Integer): Integer; external;
function gpio_get_level(pin: Integer): Integer; external;

function GpioReset(pin: Integer): Integer;
begin
  GpioReset := gpio_reset_pin(pin);
end;

function GpioSetDirection(pin, mode: Integer): Integer;
begin
  GpioSetDirection := gpio_set_direction(pin, mode);
end;

function GpioSetLevel(pin, level: Integer): Integer;
begin
  GpioSetLevel := gpio_set_level(pin, level);
end;

function GpioGetLevel(pin: Integer): Integer;
begin
  GpioGetLevel := gpio_get_level(pin);
end;

{ ---- the Nil Python surface ---------------------------------------------- }

{ Reset first: a pin can come out of boot wired to a peripheral (JTAG, the
  flash, a strapping function), and gpio_set_direction alone does not take it
  back. Returns the first rc that is not ESP_OK, so one number answers both
  calls. }
function gpio_output(pin: Integer): Integer;
var rc: Integer;
begin
  rc := gpio_reset_pin(pin);
  if rc <> 0 then begin gpio_output := rc; Exit; end;
  gpio_output := gpio_set_direction(pin, GPIO_MODE_OUTPUT);
end;

function gpio_write(pin, level: Integer): Integer;
begin
  gpio_write := gpio_set_level(pin, level);
end;

function gpio_read(pin: Integer): Integer;
begin
  gpio_read := gpio_get_level(pin);
end;

end.
