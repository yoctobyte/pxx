{ SPDX-License-Identifier: Zlib }
unit mimic__onewire;
{$MODE PXX}   { our dialect; the FPC-parity strict-* flags do not judge this file }
{ MicroPython's `_onewire` module, the C half that micropython-lib's
  onewire.py imports:

      import _onewire as _ow
      _ow.reset(pin); _ow.writebyte(pin, 0xCC); _ow.readbyte(pin); _ow.crc8(buf)

  so onewire.py, and ds18x20.py on top of it, compile UNCHANGED. The bus
  timing is espmpyport's translation of MicroPython's extmod/modonewire.c.
  onewire.py configures the pin itself (Pin.OPEN_DRAIN, Pin.PULL_UP); nothing
  here reconfigures it.

  Only for an ESP build (the file lives in lib/rtl/platform/esp). }

interface

uses pylib, mimic_machine, espmpyport;

{ True when a device answered the reset with a presence pulse. }
function reset(pin: Pin): Boolean;
function readbit(pin: Pin): Integer;
function readbyte(pin: Pin): Integer;
procedure writebit(pin: Pin; value: Integer);
procedure writebyte(pin: Pin; value: Integer);
{ Dallas/Maxim CRC-8 of the buffer; 0 over a buffer that ends in its CRC. }
function crc8(data: TPyBytes): Integer;

implementation

function reset(pin: Pin): Boolean;
begin
  reset := MpyOneWireReset(pin.id);
end;

function readbit(pin: Pin): Integer;
begin
  readbit := MpyOneWireReadbit(pin.id);
end;

function readbyte(pin: Pin): Integer;
begin
  readbyte := MpyOneWireReadbyte(pin.id);
end;

procedure writebit(pin: Pin; value: Integer);
begin
  MpyOneWireWritebit(pin.id, value);
end;

procedure writebyte(pin: Pin; value: Integer);
begin
  MpyOneWireWritebyte(pin.id, value);
end;

function crc8(data: TPyBytes): Integer;
begin
  crc8 := MpyOneWireCrc8(PByte(data.FData), data.FLen);
end;

end.
