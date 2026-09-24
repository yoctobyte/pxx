{ SPDX-License-Identifier: 0BSD }
program EspPwmCheck;
{ PWM ON A PIN, MEASURED BY THE SAME CHIP, WITH NOTHING WIRED TO IT.

  lib/rtl/platform/esp/esppwm.pas drives a pin from the LEDC peripheral. The
  pin's input path stays enabled, and the pad feeds its own input, so the chip
  can watch what it is driving:
    frequency  rising edges counted for one second by espgpio's edge interrupt
    duty       the pin's level sampled 20,000 times at an interval that does
               not divide the period, as the share of samples that read 1
  Rows and tolerances (ISR latency and sampling are the only error sources):
    1 kHz, 250 per mille     edges 1000 +-2 %, duty 25 % +-3
    duty 750                 duty 75 % +-3
    freq 5 kHz (the resolution changes 14 -> 11 bits; the duty must survive it)
                             edges 5000 +-2 %, duty 75 % +-3
    50 Hz, pulse 1500 us     edges 50 +-1, duty 7.5 % +-1.5 (a servo's centre)
    stop                     NO edges in the next 200 ms: the control that the
                             counts above came from the PWM and nothing else
    a fifth pin              refused with ESP_ERR_NOT_FOUND ($105)
  Each row prints PASS or FAIL; the last line is PWM-CHECK-DONE with counts. }

uses esppwm, espgpio;

procedure esp_rom_printf(fmt: string; v: Integer); external;
procedure esp_rom_delay_us(us: Integer); external;
procedure vTaskDelay(ticks: Integer); external;
function gpio_input_enable(pin: Integer): Integer; external;

const
  PIN_A = 5;
  PIN_B = 6;

var
  Passed, Failed: Integer;

procedure Row(name: string; ok: Boolean; detail: Integer);
begin
  esp_rom_printf(name, 0);
  if ok then begin esp_rom_printf(' PASS (%d)'#10, detail); Passed := Passed + 1; end
  else begin esp_rom_printf(' FAIL (%d)'#10, detail); Failed := Failed + 1; end;
end;

{ Rising edges on pin over ms milliseconds. }
function EdgesIn(pin, ms: Integer): Integer;
var e0: Integer;
begin
  GpioArmEdge(pin, GPIO_EDGE_RISING);
  e0 := GpioEdgeCount;
  vTaskDelay(ms div 10);
  EdgesIn := GpioEdgeCount - e0;
  GpioArmEdge(pin, GPIO_EDGE_NONE);
end;

{ Per mille of 20,000 level samples that read 1. }
function DutyMeasured(pin: Integer): Integer;
var i, hi: Integer;
begin
  hi := 0;
  for i := 1 to 20000 do
  begin
    if GpioGetLevel(pin) <> 0 then hi := hi + 1;
    esp_rom_delay_us(7);
  end;
  DutyMeasured := hi div 20;
end;

function Near(v, want, tol: Integer): Boolean;
begin
  Near := (v >= want - tol) and (v <= want + tol);
end;

var rc, e, d: Integer;
begin
  esp_rom_printf('PWM-CHECK on GPIO%d', PIN_A);
  esp_rom_printf(' and GPIO%d'#10, PIN_B);

  rc := PwmStart(PIN_A, 1000, 250);
  gpio_input_enable(PIN_A);
  Row('start 1kHz', rc = 0, rc);
  Row('bits 1kHz', PwmBits(PIN_A) = 14, PwmBits(PIN_A));
  e := EdgesIn(PIN_A, 1000);
  Row('edges 1kHz', Near(e, 1000, 20), e);
  d := DutyMeasured(PIN_A);
  Row('duty 250', Near(d, 250, 30), d);

  rc := PwmSetDuty(PIN_A, 750);
  vTaskDelay(2);
  d := DutyMeasured(PIN_A);
  Row('duty 750', (rc = 0) and Near(d, 750, 30), d);

  rc := PwmSetFreq(PIN_A, 5000);
  vTaskDelay(2);
  Row('freq 5kHz rc', rc = 0, rc);
  Row('bits 5kHz', PwmBits(PIN_A) = 11, PwmBits(PIN_A));
  e := EdgesIn(PIN_A, 1000);
  Row('edges 5kHz', Near(e, 5000, 100), e);
  d := DutyMeasured(PIN_A);
  Row('duty kept', Near(d, 750, 30), d);

  rc := PwmStart(PIN_B, 50, 0);
  gpio_input_enable(PIN_B);
  if rc = 0 then rc := PwmSetPulseUs(PIN_B, 1500);
  vTaskDelay(5);
  Row('servo start', rc = 0, rc);
  e := EdgesIn(PIN_B, 1000);
  Row('edges 50Hz', Near(e, 50, 1), e);
  d := DutyMeasured(PIN_B);
  Row('pulse 1500us', Near(d, 75, 15), d);

  rc := PwmStop(PIN_A);
  vTaskDelay(2);
  e := EdgesIn(PIN_A, 200);
  Row('stopped', (rc = 0) and (e = 0), e);

  { four slots: B is running, fill three more, then a fifth must be refused }
  rc := PwmStart(7, 1000, 500);
  if rc = 0 then rc := PwmStart(8, 1000, 500);
  if rc = 0 then rc := PwmStart(9, 1000, 500);
  Row('four pins', rc = 0, rc);
  rc := PwmStart(10, 1000, 500);
  Row('fifth refused', rc = $105, rc);
  PwmStop(PIN_B); PwmStop(7); PwmStop(8); PwmStop(9);

  esp_rom_printf('PWM-CHECK-DONE passed=%d', Passed);
  esp_rom_printf(' failed=%d'#10, Failed);
  while True do vTaskDelay(1000);
end.
