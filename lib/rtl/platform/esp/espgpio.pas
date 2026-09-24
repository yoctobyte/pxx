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
  in its REQUIRES.

  EDGE INTERRUPTS: THE GPIO SOURCE FOR lib/rtl/interrupts.pas
  (feature-esp-gpio-and-adc-callback-slices, slice 2). on_rising / on_falling /
  on_change ARM a pin; they take no callback. The ISR this unit installs does
  exactly two things, counts the entry and calls interrupts.IntPush(INT_SRC_GPIO,
  pin), so no application code, Pascal or Python, runs in interrupt context.
  That is the owner's design (2026-09-22). A handler is registered on the
  consumer side instead, `interrupts.on_event(interrupts.INT_SRC_GPIO, h)`, and
  it runs at the next blocking point (time.sleep, sysutils.Sleep) or at an
  explicit interrupts.poll(). The event's `id` is the pin.

  Measured on an ESP32-S3 board, not under qemu, which models no GPIO input
  path. examples/esp32/gpio-edge-s3 is the acceptance: ordering (nothing is
  delivered at edge time) and count (ISR entries == delivered + dropped), with
  the edge made by a pin in INPUT_OUTPUT mode, whose pad feeds its own input.

  The GPIO ISR service is installed with flags 0, so it is NOT an IRAM
  interrupt. It is deferred while the flash cache is off (during a flash
  write), and in exchange the handler and IntPush may live in flash like
  everything else here. }

interface

const
  { gpio_mode_t, from hal/gpio_types.h: BIT0 input, BIT1 output, BIT2 open-drain }
  GPIO_MODE_DISABLE      = 0;
  GPIO_MODE_INPUT        = 1;
  GPIO_MODE_OUTPUT       = 2;
  GPIO_MODE_INPUT_OUTPUT = 3;

  { gpio_int_type_t, from hal/gpio_types.h, under our own names }
  GPIO_EDGE_NONE    = 0;   { GPIO_INTR_DISABLE; renamed, it is the same identifier as gpio_intr_disable }
  GPIO_EDGE_RISING  = 1;   { GPIO_INTR_POSEDGE }
  GPIO_EDGE_FALLING = 2;   { GPIO_INTR_NEGEDGE }
  GPIO_EDGE_ANY     = 3;   { GPIO_INTR_ANYEDGE }

{ Pascal surface. Each returns the SDK's esp_err_t; 0 is ESP_OK. }
function GpioReset(pin: Integer): Integer;
function GpioSetDirection(pin, mode: Integer): Integer;
function GpioSetLevel(pin, level: Integer): Integer;
function GpioGetLevel(pin: Integer): Integer;

{ Arm pin to push an interrupts event (INT_SRC_GPIO, pin) on each edge of the
  given GPIO_EDGE_* kind; GPIO_EDGE_NONE disarms it. Does NOT change the
  pin's direction -- configure it as an input (or INPUT_OUTPUT) first. Returns
  the first esp_err_t that is not ESP_OK. }
function GpioArmEdge(pin, kind: Integer): Integer;
{ ISR entries since boot, counted by the ISR itself before it pushes. This is
  the producer-side count that makes `pushed == delivered + dropped` checkable
  against something the queue did not compute. }
function GpioEdgeCount: Integer;

{ ---- the Nil Python surface ----------------------------------------------
  Plain ints in and out, so it crosses the seam with no marshalling question:

      import 'espgpio.pas' as gpio
      gpio.gpio_output(8)          # reset the pin and drive it
      gpio.gpio_write(8, 1)

  gpio_read is the one that emulation cannot answer; see the header. }
function gpio_output(pin: Integer): Integer;
function gpio_write(pin, level: Integer): Integer;
function gpio_read(pin: Integer): Integer;

{ Reset the pin and make it an input. gpio_reset_pin leaves the pull-up on,
  so a button to ground reads 1 at rest and gives a falling edge when pressed. }
function gpio_input(pin: Integer): Integer;
{ Drive the pin AND read it. The pad feeds its own input path, so writing it
  makes a real edge that the interrupt hardware sees, with nothing wired. }
function gpio_inout(pin: Integer): Integer;

{ Internal pull resistor on a pin, digital or analog. On an ADC pad, set it
  AFTER adc start: the ADC driver clears the pulls when it claims the pad. }
function gpio_pullup(pin: Integer): Integer;
function gpio_pulldown(pin: Integer): Integer;

{ Arm edge interrupts on a pin; each edge becomes an interrupts event with
  source interrupts.INT_SRC_GPIO and id = pin. Register the handler with
  interrupts.on_event. edge_off disarms. All return an esp_err_t, 0 = ESP_OK. }
function on_rising(pin: Integer): Integer;
function on_falling(pin: Integer): Integer;
function on_change(pin: Integer): Integer;
function edge_off(pin: Integer): Integer;
{ ISR entries since boot; see GpioEdgeCount. }
function gpio_edges: Integer;

implementation

uses interrupts;   { IntPush -- the only thing the ISR below calls }

{ components/esp_driver_gpio. All resolve at IDF link time. }
function gpio_reset_pin(pin: Integer): Integer; external;
function gpio_set_direction(pin, mode: Integer): Integer; external;
function gpio_set_level(pin, level: Integer): Integer; external;
function gpio_get_level(pin: Integer): Integer; external;
function gpio_set_intr_type(pin, kind: Integer): Integer; external;
function gpio_intr_enable(pin: Integer): Integer; external;
function gpio_intr_disable(pin: Integer): Integer; external;
function gpio_install_isr_service(flags: Integer): Integer; external;
function gpio_isr_handler_add(pin: Integer; isr: Pointer; arg: Pointer): Integer; external;
function gpio_isr_handler_remove(pin: Integer): Integer; external;
function gpio_set_pull_mode(pin, mode: Integer): Integer; external;

const
  ESP_ERR_INVALID_STATE = $103;   { install_isr_service: already installed }

var
  EdgeIsrCount: LongInt;
  IsrServiceUp: Boolean;
  { one live source (interrupts.IntSourceOpen) per armed pin }
  Armed: array[0 .. 63] of Boolean;

{ INTERRUPT CONTEXT. Called by the IDF GPIO ISR service with the pin as arg.
  Counts the entry and pushes; nothing else, and in particular no callback.
  The count is written only here, so a plain increment is enough: the one
  reader is ordinary code, and a 32-bit aligned load cannot tear. }
procedure EdgeIsr(arg: Pointer);
begin
  EdgeIsrCount := EdgeIsrCount + 1;
  IntPush(INT_SRC_GPIO, Integer(PtrUInt(arg)));
end;

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

function GpioArmEdge(pin, kind: Integer): Integer;
var rc: Integer;
begin
  if kind = GPIO_EDGE_NONE then
  begin
    rc := gpio_intr_disable(pin);
    gpio_isr_handler_remove(pin);
    gpio_set_intr_type(pin, GPIO_EDGE_NONE);
    if (pin >= 0) and (pin <= 63) and Armed[pin] then
    begin
      Armed[pin] := False;
      IntSourceClose;
    end;
    GpioArmEdge := rc;
    Exit;
  end;
  if not IsrServiceUp then
  begin
    { Another component may have installed the service already; that is
      success for us, not an error. }
    rc := gpio_install_isr_service(0);
    if (rc <> 0) and (rc <> ESP_ERR_INVALID_STATE) then
    begin
      GpioArmEdge := rc;
      Exit;
    end;
    IsrServiceUp := True;
  end;
  rc := gpio_set_intr_type(pin, kind);
  if rc <> 0 then begin GpioArmEdge := rc; Exit; end;
  rc := gpio_isr_handler_add(pin, @EdgeIsr, Pointer(PtrUInt(pin)));
  if rc <> 0 then begin GpioArmEdge := rc; Exit; end;
  rc := gpio_intr_enable(pin);
  if (rc = 0) and (pin >= 0) and (pin <= 63) and not Armed[pin] then
  begin
    Armed[pin] := True;
    IntSourceOpen;
  end;
  GpioArmEdge := rc;
end;

function GpioEdgeCount: Integer;
begin
  GpioEdgeCount := EdgeIsrCount;
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

function gpio_input(pin: Integer): Integer;
var rc: Integer;
begin
  rc := gpio_reset_pin(pin);
  if rc <> 0 then begin gpio_input := rc; Exit; end;
  gpio_input := gpio_set_direction(pin, GPIO_MODE_INPUT);
end;

function gpio_inout(pin: Integer): Integer;
var rc: Integer;
begin
  rc := gpio_reset_pin(pin);
  if rc <> 0 then begin gpio_inout := rc; Exit; end;
  gpio_inout := gpio_set_direction(pin, GPIO_MODE_INPUT_OUTPUT);
end;

function gpio_pullup(pin: Integer): Integer;
begin
  gpio_pullup := gpio_set_pull_mode(pin, 0);     { GPIO_PULLUP_ONLY }
end;

function gpio_pulldown(pin: Integer): Integer;
begin
  gpio_pulldown := gpio_set_pull_mode(pin, 1);   { GPIO_PULLDOWN_ONLY }
end;

function on_rising(pin: Integer): Integer;
begin
  on_rising := GpioArmEdge(pin, GPIO_EDGE_RISING);
end;

function on_falling(pin: Integer): Integer;
begin
  on_falling := GpioArmEdge(pin, GPIO_EDGE_FALLING);
end;

function on_change(pin: Integer): Integer;
begin
  on_change := GpioArmEdge(pin, GPIO_EDGE_ANY);
end;

function edge_off(pin: Integer): Integer;
begin
  edge_off := GpioArmEdge(pin, GPIO_EDGE_NONE);
end;

function gpio_edges: Integer;
begin
  gpio_edges := EdgeIsrCount;
end;

end.
