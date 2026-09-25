{ SPDX-License-Identifier: Zlib }
unit mimic_binascii;
{$MODE PXX}   { our dialect; the FPC-parity strict-* flags do not judge this file }
{ Python's `binascii`, the subset MicroPython's networking libraries import.

  `import binascii` RESOLVES here through the NilPy import resolver's `mimic_`
  fallback; `--no-shims` turns it into an error.

  WHO ASKED: umqtt.simple and mqtt_as (`from binascii import hexlify`), found by
  `tools/mpy_driver_census.sh net`. MicroPython's own binascii has hexlify,
  unhexlify, a2b_base64, b2a_base64 and crc32; the first four are here.

  hexlify(data, sep) takes a str separator (MicroPython's `hexlify(mac, ':')`);
  CPython also accepts bytes there and a bytes_per_sep count, neither of which
  a library in the census writes. unhexlify raises `Error`, a ValueError, on an
  odd length or a non-hex digit, as both CPython and MicroPython do.

  ABSENT: crc32 (zlib.crc32 is the same function and is already in zlib.pas),
  the uu/qp/hqx codecs, which MicroPython does not carry either. }

interface

uses hashing, pylib, pymarshal, base64;   { TByteArray }

type
  Error = class(ValueError) end;

function hexlify(const data: Variant; const sep: AnsiString = ''): TPyBytes;
function unhexlify(const data: Variant): TPyBytes;
function a2b_base64(const data: Variant): TPyBytes;
function b2a_base64(const data: Variant; newline: Boolean = True): TPyBytes;

implementation

const
  HexDigits: AnsiString = '0123456789abcdef';

function hexlify(const data: Variant; const sep: AnsiString = ''): TPyBytes;
var raw: TByteArray; s: AnsiString; i: Integer;
begin
  raw := PyToBytes(data);
  s := '';
  for i := 0 to Length(raw) - 1 do
  begin
    if (i > 0) and (sep <> '') then s := s + sep;
    s := s + HexDigits[(raw[i] shr 4) + 1] + HexDigits[(raw[i] and 15) + 1];
  end;
  hexlify := StrToPy(s);
end;

function HexValue(c: AnsiChar): Integer;
begin
  case c of
    '0'..'9': HexValue := Ord(c) - Ord('0');
    'a'..'f': HexValue := Ord(c) - Ord('a') + 10;
    'A'..'F': HexValue := Ord(c) - Ord('A') + 10;
  else
    HexValue := -1;
  end;
end;

function unhexlify(const data: Variant): TPyBytes;
var s, outs: AnsiString; i, hi, lo: Integer;
begin
  s := PyToText(data);
  if Odd(Length(s)) then
    raise Error.Create('Odd-length string');
  outs := '';
  i := 1;
  while i < Length(s) do
  begin
    hi := HexValue(s[i]);
    lo := HexValue(s[i + 1]);
    if (hi < 0) or (lo < 0) then
      raise Error.Create('Non-hexadecimal digit found');
    outs := outs + AnsiChar(hi * 16 + lo);
    i := i + 2;
  end;
  unhexlify := StrToPy(outs);
end;

function a2b_base64(const data: Variant): TPyBytes;
begin
  a2b_base64 := b64decode(data);
end;

function b2a_base64(const data: Variant; newline: Boolean = True): TPyBytes;
var s: AnsiString;
begin
  s := Base64Encode(PyToBytes(data));
  if newline then s := s + #10;
  b2a_base64 := StrToPy(s);
end;

end.
