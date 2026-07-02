{ SPDX-License-Identifier: Zlib }
unit bitset;
{ Dynamic bit vector over packed Integer words. 0-based indexing.
  Track B; uses 32-bit words with proven ops (or/and/xor/shl/shr).
  Avoids `not` — the pinned stable treats it as boolean on Integer. }

interface

const
  BITARRAY_BITS_PER_WORD = 32;

type
  TBitArray = record
    bits: array of Integer;  { packed 32-bit words, little-endian }
    len: Integer;            { number of valid bits }
  end;

{ Allocate for len bits, all zero. }
procedure BitArrayInit(var ba: TBitArray; len: Integer);

{ Set / clear / flip bit at 0-based index. }
procedure BitArraySetBit(var ba: TBitArray; index: Integer);
procedure BitArrayClearBit(var ba: TBitArray; index: Integer);
procedure BitArrayToggle(var ba: TBitArray; index: Integer);

{ Test bit at 0-based index. }
function BitArrayTestBit(const ba: TBitArray; index: Integer): Boolean;

{ Count of set bits (popcount). }
function BitArrayCount(const ba: TBitArray): Integer;

{ Next set bit at or after from; -1 if none. }
function BitArrayNextSet(const ba: TBitArray; from: Integer): Integer;

implementation

procedure BitArrayInit(var ba: TBitArray; len: Integer);
var n, i: Integer;
begin
  ba.len := len;
  n := (len + BITARRAY_BITS_PER_WORD - 1) div BITARRAY_BITS_PER_WORD;
  SetLength(ba.bits, n);
  for i := 0 to n - 1 do ba.bits[i] := 0;
end;

procedure BitArraySetBit(var ba: TBitArray; index: Integer);
var w, b: Integer;
begin
  w := index div BITARRAY_BITS_PER_WORD;
  b := index mod BITARRAY_BITS_PER_WORD;
  ba.bits[w] := ba.bits[w] or (1 shl b);
end;

procedure BitArrayClearBit(var ba: TBitArray; index: Integer);
var w, b, mask, cur: Integer;
begin
  w := index div BITARRAY_BITS_PER_WORD;
  b := index mod BITARRAY_BITS_PER_WORD;
  mask := 1 shl b;
  cur := ba.bits[w];
  if (cur and mask) <> 0 then
    ba.bits[w] := cur - mask;
end;

procedure BitArrayToggle(var ba: TBitArray; index: Integer);
var w, b: Integer;
begin
  w := index div BITARRAY_BITS_PER_WORD;
  b := index mod BITARRAY_BITS_PER_WORD;
  ba.bits[w] := ba.bits[w] xor (1 shl b);
end;

function BitArrayTestBit(const ba: TBitArray; index: Integer): Boolean;
var w, b: Integer;
begin
  w := index div BITARRAY_BITS_PER_WORD;
  b := index mod BITARRAY_BITS_PER_WORD;
  Result := (ba.bits[w] and (1 shl b)) <> 0;
end;

function BitArrayCount(const ba: TBitArray): Integer;
var i, n, v: Integer;
begin
  Result := 0;
  n := Length(ba.bits);
  for i := 0 to n - 1 do
  begin
    v := ba.bits[i];
    while v <> 0 do
    begin
      Result := Result + 1;
      v := v and (v - 1);
    end;
  end;
end;

function BitArrayNextSet(const ba: TBitArray; from: Integer): Integer;
var w, b, n, v: Integer;
begin
  if from >= ba.len then begin Result := -1; Exit; end;
  w := from div BITARRAY_BITS_PER_WORD;
  b := from mod BITARRAY_BITS_PER_WORD;
  n := Length(ba.bits);
  v := ba.bits[w] shr b;
  if v <> 0 then
  begin
    Result := w * BITARRAY_BITS_PER_WORD + b;
    while (v and 1) = 0 do
    begin
      v := v shr 1;
      Result := Result + 1;
    end;
    if Result < ba.len then Exit;
    Result := -1;
    Exit;
  end;
  w := w + 1;
  while w < n do
  begin
    if ba.bits[w] <> 0 then
    begin
      Result := w * BITARRAY_BITS_PER_WORD;
      v := ba.bits[w];
      while (v and 1) = 0 do
      begin
        v := v shr 1;
        Result := Result + 1;
      end;
      if Result < ba.len then Exit;
      Result := -1;
      Exit;
    end;
    w := w + 1;
  end;
  Result := -1;
end;

end.
