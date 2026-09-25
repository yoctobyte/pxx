{ SPDX-License-Identifier: MIT }
unit espmpyport;
{$MODE PXX}   { our dialect; the FPC-parity strict-* flags do not judge this file }
{ MicroPython's microsecond pin protocols, translated line for line into
  Pascal for an ESP build, so mimic_machine and mimic__onewire answer as
  MicroPython's ESP32 port does. From micropython/micropython commit
  647c8b96cae7e202c7a020395b7cfe65e5b8ce04 (v1.26.1):

    extmod/machine_pulse.c   machine_time_pulse_us   -> MpyTimePulseUs
    drivers/dht/dht.c        dht_readinto            -> MpyDhtReadinto
    extmod/modonewire.c      onewire_bus_*, crc8     -> MpyOneWire*
    ports/esp32/mphalport.h  mp_hal_quiet_timing_*   -> MpyQuietEnter/Exit

  The timings, the order of every pin write and read, and the thresholds are
  MicroPython's; only the spelling is Pascal. Where MicroPython's ESP32 port
  enters a critical section (mp_begin_atomic_section, a portMUX), so does this,
  through the FreeRTOS functions portENTER_CRITICAL expands to on each ISA.

  Pins are numbers here: the Pin object is mimic_machine's.

  Copyright (c) 2013-2017 Damien P. George (MicroPython), and the
  translation (c) the pxx authors, under the same licence:

  Permission is hereby granted, free of charge, to any person obtaining a copy
  of this software and associated documentation files (the "Software"), to deal
  in the Software without restriction, including without limitation the rights
  to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
  copies of the Software, and to permit persons to whom the Software is
  furnished to do so, subject to the following conditions:

  The above copyright notice and this permission notice shall be included in
  all copies or substantial portions of the Software.

  THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
  IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
  FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
  AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
  LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
  OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN
  THE SOFTWARE. }

interface

uses espgpio, mimic_time;

{ mp_hal_quiet_timing_enter/exit. Keep what runs between them short. }
procedure MpyQuietEnter;
procedure MpyQuietExit;

{ machine_time_pulse_us: -2 when the pulse never started within timeout_us,
  -1 when it never ended within timeout_us, else its width in microseconds. }
function MpyTimePulseUs(pin, pulse_level: Integer; timeout_us: Int64): Int64;

{ dht_readinto's protocol on an open-drain pin: False on a timeout (the
  caller raises ETIMEDOUT). buf holds at least 5 bytes. }
function MpyDhtReadinto(pin: Integer; buf: PByte): Boolean;

function MpyOneWireReset(pin: Integer): Boolean;
function MpyOneWireReadbit(pin: Integer): Integer;
function MpyOneWireReadbyte(pin: Integer): Integer;
procedure MpyOneWireWritebit(pin, value: Integer);
procedure MpyOneWireWritebyte(pin, value: Integer);
function MpyOneWireCrc8(data: PByte; len: Integer): Integer;

implementation

type
  TPortMux = record          { spinlock_t: owner, count }
    owner, count: LongWord;
  end;

function esp_timer_get_time: Int64; external;
procedure esp_rom_delay_us(us: LongWord); external;
{$ifdef CPU_XTENSA}
{ portENTER_CRITICAL(mux) / portEXIT_CRITICAL(mux) on the Xtensa port (S3, S2,
  the classic ESP32): a spinlock, so the other core cannot run either. }
function xPortEnterCriticalTimeout(mux: Pointer; timeout: Integer): Integer; external;
procedure vPortExitCritical(mux: Pointer); external;
{$else}
{ ...and on the single-core RISC-V chips (C3, C6, H2), where the macros drop
  the mux and mask interrupts. A dual-core RISC-V (P4) aborts in these and
  would need vPortEnterCriticalMultiCore, which is an inline. }
procedure vPortEnterCritical; external;
procedure vPortExitCritical; external;
{$endif}

var
  QuietMux: TPortMux = (owner: $B33FFFFF; count: 0);   { SPINLOCK_FREE }

procedure MpyQuietEnter;
begin
  {$ifdef CPU_XTENSA}
  xPortEnterCriticalTimeout(@QuietMux, -1);             { portMUX_NO_TIMEOUT }
  {$else}
  vPortEnterCritical;
  {$endif}
end;

procedure MpyQuietExit;
begin
  {$ifdef CPU_XTENSA}
  vPortExitCritical(@QuietMux);
  {$else}
  vPortExitCritical;
  {$endif}
end;

function MpyTimePulseUs(pin, pulse_level: Integer; timeout_us: Int64): Int64;
var nchanges, t, start: Int64;
begin
  nchanges := 2;
  start := esp_timer_get_time;
  while True do
  begin
    { sample the time, then the pin, in the same order every time round }
    t := esp_timer_get_time;
    if GpioGetLevel(pin) = pulse_level then
    begin
      pulse_level := 1 - pulse_level;
      nchanges := nchanges - 1;
      if nchanges = 0 then
      begin
        MpyTimePulseUs := t - start;
        Exit;
      end;
      start := t;
    end
    else if t - start >= timeout_us then
    begin
      MpyTimePulseUs := -nchanges;
      Exit;
    end;
  end;
end;

function MpyDhtReadinto(pin: Integer; buf: PByte): Boolean;
var ticks: Int64; i: Integer;
begin
  MpyDhtReadinto := False;
  gpio_opendrain(pin);
  { issue start command }
  GpioSetLevel(pin, 1);
  sleep_ms(250);      { mp_hal_delay_ms: yields }
  GpioSetLevel(pin, 0);
  sleep_ms(18);
  MpyQuietEnter;
  { release the line so the device can respond }
  GpioSetLevel(pin, 1);
  esp_rom_delay_us(10);
  { wait for device to respond }
  ticks := esp_timer_get_time;
  while GpioGetLevel(pin) <> 0 do
    if esp_timer_get_time - ticks > 100 then
    begin
      MpyQuietExit;
      Exit;
    end;
  { time pulse, should be 80us }
  if MpyTimePulseUs(pin, 1, 150) < 0 then
  begin
    MpyQuietExit;
    Exit;
  end;
  { time 40 pulses for data (either 26us or 70us) }
  for i := 0 to 39 do
  begin
    ticks := MpyTimePulseUs(pin, 1, 100);
    if ticks < 0 then
    begin
      MpyQuietExit;
      Exit;
    end;
    buf[i div 8] := Byte((buf[i div 8] shl 1) or Ord(ticks > 48));
  end;
  MpyQuietExit;
  MpyDhtReadinto := True;
end;

const
  TIMING_RESET1 = 480;
  TIMING_RESET2 = 70;
  TIMING_RESET3 = 410;
  TIMING_READ1  = 6;
  TIMING_READ2  = 9;
  TIMING_READ3  = 55;
  TIMING_WRITE1 = 6;
  TIMING_WRITE2 = 54;
  TIMING_WRITE3 = 10;

function MpyOneWireReset(pin: Integer): Boolean;
var status: Boolean;
begin
  GpioSetLevel(pin, 0);
  esp_rom_delay_us(TIMING_RESET1);
  MpyQuietEnter;
  GpioSetLevel(pin, 1);
  esp_rom_delay_us(TIMING_RESET2);
  status := GpioGetLevel(pin) = 0;
  MpyQuietExit;
  esp_rom_delay_us(TIMING_RESET3);
  MpyOneWireReset := status;
end;

function MpyOneWireReadbit(pin: Integer): Integer;
var value: Integer;
begin
  GpioSetLevel(pin, 1);
  MpyQuietEnter;
  GpioSetLevel(pin, 0);
  esp_rom_delay_us(TIMING_READ1);
  GpioSetLevel(pin, 1);
  esp_rom_delay_us(TIMING_READ2);
  value := GpioGetLevel(pin);
  MpyQuietExit;
  esp_rom_delay_us(TIMING_READ3);
  MpyOneWireReadbit := value;
end;

function MpyOneWireReadbyte(pin: Integer): Integer;
var value, i: Integer;
begin
  value := 0;
  for i := 0 to 7 do
    value := value or (MpyOneWireReadbit(pin) shl i);
  MpyOneWireReadbyte := value;
end;

procedure MpyOneWireWritebit(pin, value: Integer);
begin
  MpyQuietEnter;
  GpioSetLevel(pin, 0);
  esp_rom_delay_us(TIMING_WRITE1);
  if value <> 0 then
    GpioSetLevel(pin, 1);
  esp_rom_delay_us(TIMING_WRITE2);
  GpioSetLevel(pin, 1);
  esp_rom_delay_us(TIMING_WRITE3);
  MpyQuietExit;
end;

procedure MpyOneWireWritebyte(pin, value: Integer);
var i: Integer;
begin
  for i := 0 to 7 do
  begin
    MpyOneWireWritebit(pin, value and 1);
    value := value shr 1;
  end;
end;

function MpyOneWireCrc8(data: PByte; len: Integer): Integer;
var crc, b, fb: Byte; i, j: Integer;
begin
  crc := 0;
  for i := 0 to len - 1 do
  begin
    b := data[i];
    for j := 0 to 7 do
    begin
      fb := (crc xor b) and $01;
      if fb = $01 then
        crc := crc xor $18;
      crc := (crc shr 1) and $7F;
      if fb = $01 then
        crc := crc or $80;
      b := b shr 1;
    end;
  end;
  MpyOneWireCrc8 := crc;
end;

end.
