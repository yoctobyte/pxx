{ SPDX-License-Identifier: Zlib }
unit esppwm;
{$MODE PXX}   { our dialect; the FPC-parity strict-* flags do not judge this file }
{ ESP32 PWM on a pin, through the LEDC peripheral. For Pascal and for Nil
  Python; plain ints in and out, so neither half needs the Python runtime.

      import 'esppwm.pas' as pwm
      pwm.start(2, 1000, 250)      # pin 2, 1 kHz, duty 250 per mille (25 %)
      pwm.duty(2, 750)             # 75 %
      pwm.pulse_us(2, 1500)        # a servo's centre: 1.5 ms high per period
      pwm.stop(2)

  Duty is PER MILLE (0..1000), not per cent: a hobby servo at 50 Hz moves over
  5..10 % of the period, and whole per cent would give it ten positions.
  pulse_us sets the high time directly, which is the unit servos are specified
  in.

  UP TO FOUR PINS AT ONCE, each with its own frequency: every pin gets its own
  LEDC channel AND its own timer, and the S2/S3/C3 have four low-speed timers.
  A fifth start() answers ESP_ERR_NOT_FOUND. Sharing one timer between pins
  would allow more of them at one frequency; nothing here needs that yet.

  The resolution is chosen per frequency: the largest of 14..1 bits for which
  freq * 2^bits fits the 80 MHz APB clock with room to spare, so 50 Hz gets 14
  bits (a servo step of ~1.2 us) and 40 kHz still gets 10.

  The config structs are mirrored below; they are safe to mirror on the S2,
  S3 and C3: LEDC_LOW_SPEED_MODE is 0 on every chip without a high-speed mode
  (only the classic ESP32 has one, where it is 1), LEDC_AUTO_CLK is 0 on all
  three, and no field is compiled in per chip. Measured against ESP-IDF
  v6.0.1's headers, 2026-09-24.

  IDF-only. A project using this unit needs esp_driver_ledc in its REQUIRES. }

interface

const
  PWM_MAX_PINS = 4;

{ Pascal surface. Each returns the SDK's esp_err_t; 0 is ESP_OK. }
function PwmStart(pin, freqHz, dutyPerMille: Integer): Integer;
function PwmSetDuty(pin, dutyPerMille: Integer): Integer;
function PwmSetPulseUs(pin, us: Integer): Integer;
function PwmSetFreq(pin, freqHz: Integer): Integer;
function PwmStop(pin: Integer): Integer;
{ The resolution in bits that PwmStart chose for pin, or 0 if it is not running. }
function PwmBits(pin: Integer): Integer;

{ ---- the Nil Python surface ---------------------------------------------- }
function start(pin, freq_hz, duty_per_mille: Integer): Integer;
function duty(pin, duty_per_mille: Integer): Integer;
function pulse_us(pin, us: Integer): Integer;
function freq(pin, freq_hz: Integer): Integer;
function stop(pin: Integer): Integer;
function bits(pin: Integer): Integer;

implementation

type
  TLedcTimerConfig = record        { ledc_timer_config_t }
    speed_mode:      Integer;
    duty_resolution: Integer;
    timer_num:       Integer;
    freq_hz:         LongWord;
    clk_cfg:         Integer;
    deconfigure:     Byte;
    pad0, pad1, pad2: Byte;
  end;
  TLedcChannelConfig = record      { ledc_channel_config_t }
    gpio_num:    Integer;
    speed_mode:  Integer;
    channel:     Integer;
    intr_type:   Integer;          { deprecated, 0 }
    timer_sel:   Integer;
    duty:        LongWord;
    hpoint:      Integer;
    sleep_mode:  Integer;
    flags:       LongWord;         { bit 0 output_invert }
    deconfigure: Byte;
    pad0, pad1, pad2: Byte;
  end;

const
  LEDC_LOW_SPEED_MODE = 0;
  LEDC_AUTO_CLK = 0;
  APB_HZ = 80000000;
  ESP_ERR_INVALID_ARG = $102;
  ESP_ERR_INVALID_STATE = $103;
  ESP_ERR_NOT_FOUND = $105;

function ledc_timer_config(cfg: Pointer): Integer; external;
function ledc_channel_config(cfg: Pointer): Integer; external;
function ledc_set_duty(mode, channel: Integer; duty: LongWord): Integer; external;
function ledc_update_duty(mode, channel: Integer): Integer; external;
function ledc_set_freq(mode, timer: Integer; freq: LongWord): Integer; external;
function ledc_stop(mode, channel: Integer; idleLevel: LongWord): Integer; external;
function ledc_timer_pause(mode, timer: Integer): Integer; external;

var
  { slot i drives LEDC channel i from LEDC timer i; -1 = free }
  SlotPin: array[0 .. PWM_MAX_PINS - 1] of Integer;
  SlotBits: array[0 .. PWM_MAX_PINS - 1] of Integer;
  SlotHz: array[0 .. PWM_MAX_PINS - 1] of Integer;
  SlotDuty: array[0 .. PWM_MAX_PINS - 1] of Integer;   { per mille, last set }
  SlotsReady: Boolean;

procedure InitSlots;
var i: Integer;
begin
  if SlotsReady then Exit;
  for i := 0 to PWM_MAX_PINS - 1 do SlotPin[i] := -1;
  SlotsReady := True;
end;

function SlotOf(pin: Integer): Integer;
var i: Integer;
begin
  InitSlots;
  SlotOf := -1;
  for i := 0 to PWM_MAX_PINS - 1 do
    if SlotPin[i] = pin then begin SlotOf := i; Exit; end;
end;

{ The largest resolution <= 14 bits with freq * 2^bits <= APB/4, i.e. at
  least four clock ticks per step. 0 when even 1 bit does not fit. }
function BitsFor(hz: Integer): Integer;
var b: Integer;
begin
  BitsFor := 0;
  if hz <= 0 then Exit;
  b := 14;
  while (b > 0) and (Int64(hz) * (Int64(1) shl b) > APB_HZ div 4) do b := b - 1;
  BitsFor := b;
end;

function DutyCounts(slot, perMille: Integer): LongWord;
begin
  if perMille < 0 then perMille := 0;
  if perMille > 1000 then perMille := 1000;
  DutyCounts := LongWord((Int64(perMille) * (Int64(1) shl SlotBits[slot])) div 1000);
end;

function ConfigTimer(slot, hz, b: Integer): Integer;
var t: TLedcTimerConfig;
begin
  FillChar(t, SizeOf(t), 0);
  t.speed_mode := LEDC_LOW_SPEED_MODE;
  t.duty_resolution := b;
  t.timer_num := slot;
  t.freq_hz := hz;
  t.clk_cfg := LEDC_AUTO_CLK;
  ConfigTimer := ledc_timer_config(@t);
end;

function PwmStart(pin, freqHz, dutyPerMille: Integer): Integer;
var slot, i, b, rc: Integer; c: TLedcChannelConfig;
begin
  InitSlots;
  if SlotOf(pin) >= 0 then begin PwmStart := ESP_ERR_INVALID_STATE; Exit; end;
  b := BitsFor(freqHz);
  if b = 0 then begin PwmStart := ESP_ERR_INVALID_ARG; Exit; end;
  slot := -1;
  for i := 0 to PWM_MAX_PINS - 1 do
    if (slot < 0) and (SlotPin[i] < 0) then slot := i;
  if slot < 0 then begin PwmStart := ESP_ERR_NOT_FOUND; Exit; end;

  rc := ConfigTimer(slot, freqHz, b);
  if rc <> 0 then begin PwmStart := rc; Exit; end;
  SlotBits[slot] := b;
  SlotHz[slot] := freqHz;
  FillChar(c, SizeOf(c), 0);
  c.gpio_num := pin;
  c.speed_mode := LEDC_LOW_SPEED_MODE;
  c.channel := slot;
  c.timer_sel := slot;
  c.duty := DutyCounts(slot, dutyPerMille);
  SlotDuty[slot] := dutyPerMille;
  rc := ledc_channel_config(@c);
  if rc = 0 then SlotPin[slot] := pin;
  PwmStart := rc;
end;

function PwmSetDuty(pin, dutyPerMille: Integer): Integer;
var slot, rc: Integer;
begin
  slot := SlotOf(pin);
  if slot < 0 then begin PwmSetDuty := ESP_ERR_INVALID_STATE; Exit; end;
  rc := ledc_set_duty(LEDC_LOW_SPEED_MODE, slot, DutyCounts(slot, dutyPerMille));
  if rc = 0 then rc := ledc_update_duty(LEDC_LOW_SPEED_MODE, slot);
  if rc = 0 then SlotDuty[slot] := dutyPerMille;
  PwmSetDuty := rc;
end;

function PwmSetPulseUs(pin, us: Integer): Integer;
var slot, rc: Integer; counts: Int64;
begin
  slot := SlotOf(pin);
  if slot < 0 then begin PwmSetPulseUs := ESP_ERR_INVALID_STATE; Exit; end;
  if us < 0 then us := 0;
  { high time / period = us * hz / 1e6, in units of 2^bits }
  counts := (Int64(us) * SlotHz[slot] * (Int64(1) shl SlotBits[slot])) div 1000000;
  if counts > (Int64(1) shl SlotBits[slot]) then counts := Int64(1) shl SlotBits[slot];
  rc := ledc_set_duty(LEDC_LOW_SPEED_MODE, slot, LongWord(counts));
  if rc = 0 then rc := ledc_update_duty(LEDC_LOW_SPEED_MODE, slot);
  if rc = 0 then
    SlotDuty[slot] := Integer((counts * 1000) shr SlotBits[slot]);
  PwmSetPulseUs := rc;
end;

function PwmSetFreq(pin, freqHz: Integer): Integer;
var slot, b, rc: Integer;
begin
  slot := SlotOf(pin);
  if slot < 0 then begin PwmSetFreq := ESP_ERR_INVALID_STATE; Exit; end;
  b := BitsFor(freqHz);
  if b = 0 then begin PwmSetFreq := ESP_ERR_INVALID_ARG; Exit; end;
  if b = SlotBits[slot] then
    rc := ledc_set_freq(LEDC_LOW_SPEED_MODE, slot, freqHz)
  else
  begin
    { a new resolution: reconfigure the timer, then re-express the last duty
      in the new number of steps so the same share of the period stays high }
    rc := ConfigTimer(slot, freqHz, b);
    if rc = 0 then
    begin
      SlotBits[slot] := b;
      rc := ledc_set_duty(LEDC_LOW_SPEED_MODE, slot, DutyCounts(slot, SlotDuty[slot]));
      if rc = 0 then rc := ledc_update_duty(LEDC_LOW_SPEED_MODE, slot);
    end;
  end;
  if rc = 0 then SlotHz[slot] := freqHz;
  PwmSetFreq := rc;
end;

function PwmStop(pin: Integer): Integer;
var slot: Integer;
begin
  slot := SlotOf(pin);
  if slot < 0 then begin PwmStop := ESP_ERR_INVALID_STATE; Exit; end;
  PwmStop := ledc_stop(LEDC_LOW_SPEED_MODE, slot, 0);
  ledc_timer_pause(LEDC_LOW_SPEED_MODE, slot);
  SlotPin[slot] := -1;
end;

function PwmBits(pin: Integer): Integer;
var slot: Integer;
begin
  slot := SlotOf(pin);
  if slot < 0 then PwmBits := 0 else PwmBits := SlotBits[slot];
end;

{ ---- the Nil Python surface ---------------------------------------------- }

function start(pin, freq_hz, duty_per_mille: Integer): Integer;
begin
  start := PwmStart(pin, freq_hz, duty_per_mille);
end;

function duty(pin, duty_per_mille: Integer): Integer;
begin
  duty := PwmSetDuty(pin, duty_per_mille);
end;

function pulse_us(pin, us: Integer): Integer;
begin
  pulse_us := PwmSetPulseUs(pin, us);
end;

function freq(pin, freq_hz: Integer): Integer;
begin
  freq := PwmSetFreq(pin, freq_hz);
end;

function stop(pin: Integer): Integer;
begin
  stop := PwmStop(pin);
end;

function bits(pin: Integer): Integer;
begin
  bits := PwmBits(pin);
end;

end.
