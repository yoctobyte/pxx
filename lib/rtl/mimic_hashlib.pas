{ SPDX-License-Identifier: Zlib }
unit mimic_hashlib;
{$MODE PXX}   { our dialect; the FPC-parity strict-* flags do not judge this file }
{ Python's `hashlib`, the part That Space Program calls: `hashlib.sha1(data)`
  and `.hexdigest()` (tsp/voice.py keys its speech cache on
  `sha1(("%s|%s" % (voice, text)).encode()).hexdigest()[:20]`). `import hashlib`
  resolves here through the NilPy import resolver's `mimic_` fallback, as
  mimic_time's header describes.

  A PASCAL unit, because SHA-1 is 32-bit word arithmetic over bytes, and the
  RTL had no SHA-1 at all (sha256.pas and sha512.pas are the others). The
  algorithm is FIPS 180-4 section 6.1. A cache key is not a security use, and
  that is the only use here; SHA-1 is broken for collision resistance and
  nothing new should choose it.

  HASH OBJECTS BUFFER THEIR INPUT: `update` appends and `digest` hashes the
  whole buffer. That is O(total input) memory rather than CPython's constant
  state. It is correct, and it is the right trade for keys a few hundred bytes
  long; a caller hashing a large file in chunks would want the streaming form,
  and it is one refactor away when someone does.

  The subset: sha1, and on the object `update`, `digest`, `hexdigest`, `name`,
  `digest_size`, `block_size`. Absent: `new`, `md5`, the sha2/sha3/blake
  families (sha256.pas and sha512.pas could back two of them), `copy`,
  `file_digest`. A missing name fails at its call site. }

interface

uses pylib, sysutils;

type
  { CPython calls this type `_hashlib.HASH`. }
  HASH = class
  public
    name: AnsiString;
    digest_size: Integer;
    block_size: Integer;
    FBuf: AnsiString;
    procedure update(data: TPyBytes);
    function digest: TPyBytes;
    function hexdigest: AnsiString;
  end;

{ A SHA-1 hash object, primed with `data`. }
function sha1(data: TPyBytes): HASH;

{ Pascal surface: the 20-byte SHA-1 of `msg`, as raw bytes in a string. }
function Sha1Raw(const msg: AnsiString): AnsiString;

implementation

function Rol(x: LongWord; n: Integer): LongWord;
begin
  Result := (x shl n) or (x shr (32 - n));
end;

function Sha1Raw(const msg: AnsiString): AnsiString;
var
  h0, h1, h2, h3, h4, a, b, c, d, e, f, k, t: LongWord;
  w: array[0..79] of LongWord;
  m: AnsiString;
  bitLen: Int64;
  i, j, blk: Integer;
begin
  h0 := $67452301; h1 := $EFCDAB89; h2 := $98BADCFE; h3 := $10325476; h4 := $C3D2E1F0;
  { Pad: a 1 bit, zeros to 56 mod 64, then the bit length big-endian. }
  bitLen := Int64(Length(msg)) * 8;
  m := msg + #$80;
  while (Length(m) mod 64) <> 56 do m := m + #0;
  for i := 7 downto 0 do m := m + Chr((bitLen shr (i * 8)) and $FF);
  blk := 0;
  while blk < Length(m) do
  begin
    for j := 0 to 15 do
      w[j] := (LongWord(Ord(m[blk + j * 4 + 1])) shl 24) or (LongWord(Ord(m[blk + j * 4 + 2])) shl 16)
              or (LongWord(Ord(m[blk + j * 4 + 3])) shl 8) or LongWord(Ord(m[blk + j * 4 + 4]));
    for j := 16 to 79 do
      w[j] := Rol(w[j - 3] xor w[j - 8] xor w[j - 14] xor w[j - 16], 1);
    a := h0; b := h1; c := h2; d := h3; e := h4;
    for j := 0 to 79 do
    begin
      if j < 20 then begin f := (b and c) or ((not b) and d); k := $5A827999; end
      else if j < 40 then begin f := b xor c xor d; k := $6ED9EBA1; end
      else if j < 60 then begin f := (b and c) or (b and d) or (c and d); k := $8F1BBCDC; end
      else begin f := b xor c xor d; k := $CA62C1D6; end;
      t := Rol(a, 5) + f + e + k + w[j];
      e := d; d := c; c := Rol(b, 30); b := a; a := t;
    end;
    h0 := h0 + a; h1 := h1 + b; h2 := h2 + c; h3 := h3 + d; h4 := h4 + e;
    blk := blk + 64;
  end;
  Result := '';
  for i := 3 downto 0 do Result := Result + Chr((h0 shr (i * 8)) and $FF);
  for i := 3 downto 0 do Result := Result + Chr((h1 shr (i * 8)) and $FF);
  for i := 3 downto 0 do Result := Result + Chr((h2 shr (i * 8)) and $FF);
  for i := 3 downto 0 do Result := Result + Chr((h3 shr (i * 8)) and $FF);
  for i := 3 downto 0 do Result := Result + Chr((h4 shr (i * 8)) and $FF);
end;

procedure HASH.update(data: TPyBytes);
var i: Integer;
begin
  for i := 0 to data.count - 1 do
    FBuf := FBuf + Chr(data.at(i));
end;

function HASH.digest: TPyBytes;
var raw: AnsiString;
    i: Integer;
begin
  raw := Sha1Raw(FBuf);
  Result := TPyBytes.Create(Length(raw));
  for i := 1 to Length(raw) do
    Result.put(i - 1, Ord(raw[i]));
end;

function HASH.hexdigest: AnsiString;
const
  DIGITS: AnsiString = '0123456789abcdef';
var raw: AnsiString;
    i: Integer;
begin
  raw := Sha1Raw(FBuf);
  Result := '';
  for i := 1 to Length(raw) do
    Result := Result + DIGITS[(Ord(raw[i]) shr 4) + 1] + DIGITS[(Ord(raw[i]) and $0F) + 1];
end;

function sha1(data: TPyBytes): HASH;
begin
  Result := HASH.Create;
  Result.name := 'sha1';
  Result.digest_size := 20;
  Result.block_size := 64;
  Result.FBuf := '';
  Result.update(data);
end;

end.
