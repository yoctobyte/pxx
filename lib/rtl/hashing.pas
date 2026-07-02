{ SPDX-License-Identifier: Zlib }
unit hashing;
{ Reusable CRC32 and Adler32 checksums.

  CRC32: ISO 3309 / ITU-T V.42 polynomial used by PNG, zlib, gzip, zip.
  Adler32: zlib checksum per RFC 1950. }

interface

const
  CRC_POLY  = $EDB88320;
  ADLER_MOD = 65521;

type
  TByteArray = array of Byte;

{ CRC32 streaming interface. }
function CRC32Init: LongWord;
function CRC32Update(crc: LongWord; b: Byte): LongWord;
function CRC32Final(crc: LongWord): LongWord;

{ One-shot convenience: CRC32 of a byte array. }
function CRC32Bytes(const data: TByteArray): LongWord;
{ CRC32 over chunk-type word prepended to payload (PNG chunk CRC). }
function CRC32Chunk(kind: LongWord; const payload: TByteArray): LongWord;

{ Adler32 of a byte array (RFC 1950). }
function Adler32(const data: TByteArray): LongWord;

implementation

function CRC32Init: LongWord;
begin
  Result := LongWord($FFFFFFFF);
end;

function CRC32Update(crc: LongWord; b: Byte): LongWord;
var i: Integer;
begin
  crc := crc xor LongWord(b);
  for i := 0 to 7 do
  begin
    if (crc and 1) <> 0 then
      crc := (crc shr 1) xor CRC_POLY
    else
      crc := crc shr 1;
  end;
  Result := crc;
end;

function CRC32Final(crc: LongWord): LongWord;
begin
  Result := crc xor LongWord($FFFFFFFF);
end;

function CRC32Bytes(const data: TByteArray): LongWord;
var crc: LongWord; i: Integer;
begin
  crc := CRC32Init;
  for i := 0 to Length(data) - 1 do
    crc := CRC32Update(crc, data[i]);
  Result := CRC32Final(crc);
end;

function CRC32Chunk(kind: LongWord; const payload: TByteArray): LongWord;
var crc: LongWord; i: Integer;
begin
  crc := CRC32Init;
  crc := CRC32Update(crc, Byte((kind shr 24) and $FF));
  crc := CRC32Update(crc, Byte((kind shr 16) and $FF));
  crc := CRC32Update(crc, Byte((kind shr 8) and $FF));
  crc := CRC32Update(crc, Byte(kind and $FF));
  for i := 0 to Length(payload) - 1 do
    crc := CRC32Update(crc, payload[i]);
  Result := CRC32Final(crc);
end;

function Adler32(const data: TByteArray): LongWord;
var a, b: LongWord; i: Integer;
begin
  a := 1;
  b := 0;
  for i := 0 to Length(data) - 1 do
  begin
    a := (a + LongWord(data[i])) mod ADLER_MOD;
    b := (b + a) mod ADLER_MOD;
  end;
  Result := (b shl 16) or a;
end;

end.
