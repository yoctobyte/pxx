unit zlib;
{ zlib/deflate inflate (RFC 1950 / RFC 1951).

  Supports all three deflate block types:
    btype=0  stored (uncompressed)
    btype=1  fixed Huffman codes
    btype=2  dynamic Huffman codes

  Entry points:
    InflateZlib(input, output, error) — unwrap zlib header, inflate all blocks,
      verify Adler32. Returns True on success.
    DeflateZlibStored(input, output) — wrap input in a zlib stream using only
      uncompressed deflate blocks (valid zlib, trivial compression). }

interface

uses hashing;

function InflateZlib(const src: TByteArray; var dst: TByteArray;
                     var err: AnsiString): Boolean;

procedure DeflateZlibStored(const src: TByteArray; var dst: TByteArray);

implementation

{ ---- global inflate state ---- }
{ The pinned stable compiler has trouble with dynamic arrays stored in records
  and with passing dynamic arrays through several parameter layers. We keep the
  input array and current bit position as module globals during inflate; the
  unit is not reentrant, which matches the single-threaded RTL usage. }

var
  gData:    TByteArray;
  gBitPos:  Integer;
  gOk:      Boolean;
  gDst:     TByteArray;
  gDLen:    Integer;
  gDefDst:  TByteArray;   { module-global deflate output buffer }

function Avail(n: Integer): Boolean;
begin
  Result := gBitPos + n <= Length(gData) * 8;
end;

function ReadBits(n: Integer): Integer;
var i, bytePos, bit: Integer;
begin
  Result := 0;
  if not Avail(n) then
  begin
    gOk := False;
    Exit;
  end;
  for i := 0 to n - 1 do
  begin
    bytePos := (gBitPos + i) div 8;
    bit := (gData[bytePos] shr ((gBitPos + i) mod 8)) and 1;
    Result := Result or (bit shl i);
  end;
  gBitPos := gBitPos + n;
end;

procedure SkipBits(n: Integer);
begin
  gBitPos := gBitPos + n;
end;

procedure ByteAlign;
begin
  if (gBitPos mod 8) <> 0 then
    gBitPos := ((gBitPos div 8) + 1) * 8;
end;

function BytePos: Integer;
begin
  Result := gBitPos div 8;
end;

{ ---- dynamic array helpers ---- }

procedure DstAppend(b: Integer);
var newcap: Integer;
begin
  if gDLen >= Length(gDst) then
  begin
    newcap := Length(gDst) * 2;
    if newcap < 256 then newcap := 256;
    SetLength(gDst, newcap);
  end;
  gDst[gDLen] := Byte(b);
  gDLen := gDLen + 1;
end;

procedure DstTrim;
begin
  SetLength(gDst, gDLen);
end;

{ ---- Huffman decoder ---- }

const
  FAST_BITS = 9;    { first-level table width }
  FAST_SIZE = 512;  { 2^FAST_BITS }
  INVALID_SYM = -1;

type
  THuffTable = record
    { fast[i] = (sym shl 4) or codelen, for codes fitting in FAST_BITS bits.
      Unused entries are INVALID_SYM shl 4. }
    fast:  array[0..511] of Integer;
    { Slow path: sorted (code, codelen, sym) tuples for codes > FAST_BITS. }
    slowCode: array[0..319] of LongWord;
    slowLen:  array[0..319] of Integer;
    slowSym:  array[0..319] of Integer;
    nSlow:    Integer;
    maxLen:   Integer;
  end;

procedure HuffBuild(var ht: THuffTable; const lens: array of Integer;
                    base, nsym: Integer);
var i, j, bits, code, sym, codelen: Integer;
    count: array[0..15] of Integer;
    next:  array[0..15] of Integer;
    codes: array[0..319] of Integer;
    entry: Integer;
begin
  { clear }
  ht.maxLen := 0;
  ht.nSlow  := 0;
  for i := 0 to FAST_SIZE - 1 do
    ht.fast[i] := INVALID_SYM shl 4;

  { count codes per length }
  for i := 0 to 15 do count[i] := 0;
  for i := 0 to nsym - 1 do
    if lens[base + i] > 0 then
    begin
      count[lens[base + i]] := count[lens[base + i]] + 1;
      if lens[base + i] > ht.maxLen then ht.maxLen := lens[base + i];
    end;

  { compute first code at each length }
  code := 0;
  next[0] := 0;
  for i := 1 to 15 do
  begin
    code := (code + count[i - 1]) shl 1;
    next[i] := code;
  end;

  { assign codes }
  for i := 0 to nsym - 1 do codes[i] := -1;
  for i := 0 to nsym - 1 do
    if lens[base + i] > 0 then
    begin
      codes[i] := next[lens[base + i]];
      next[lens[base + i]] := next[lens[base + i]] + 1;
    end;

  { build lookup tables }
  for sym := 0 to nsym - 1 do
  begin
    codelen := lens[base + sym];
    if (codelen <= 0) or (codes[sym] < 0) then Continue;
    code := codes[sym];
    if codelen <= FAST_BITS then
    begin
      { reverse the code bits (deflate sends LSB first) }
      bits := 0;
      j := 0;
      while j < codelen do
      begin
        bits := (bits shl 1) or ((code shr j) and 1);
        j := j + 1;
      end;
      { fill all extensions in the fast table }
      i := bits;
      while i < FAST_SIZE do
      begin
        ht.fast[i] := (sym shl 4) or codelen;
        i := i + (1 shl codelen);
      end;
    end
    else
    begin
      { slow path entry }
      j := ht.nSlow;
      { reverse bits }
      bits := 0;
      i := 0;
      while i < codelen do
      begin
        bits := (bits shl 1) or ((code shr i) and 1);
        i := i + 1;
      end;
      ht.slowCode[j] := LongWord(bits);
      ht.slowLen[j]  := codelen;
      ht.slowSym[j]  := sym;
      ht.nSlow := j + 1;
    end;
  end;
end;

function HuffDecode(const ht: THuffTable): Integer;
var peek, entry, codelen, sym, code, bits, i: Integer;
    savedPos: Integer;
begin
  Result := INVALID_SYM;

  { fast path: peek FAST_BITS bits without consuming }
  if not Avail(FAST_BITS) then begin gOk := False; Exit; end;
  peek := 0;
  savedPos := gBitPos;
  for i := 0 to FAST_BITS - 1 do
  begin
    peek := peek or (((gData[savedPos div 8] shr (savedPos mod 8)) and 1) shl i);
    savedPos := savedPos + 1;
  end;
  entry := ht.fast[peek];
  if entry <> (INVALID_SYM shl 4) then
  begin
    codelen := entry and $F;
    sym     := entry shr 4;
    gBitPos := gBitPos + codelen;
    Result := sym;
    Exit;
  end;

  { slow path: the first FAST_BITS bits did not decode; try longer codes. }
  for codelen := FAST_BITS + 1 to ht.maxLen do
  begin
    if not Avail(codelen) then begin gOk := False; Exit; end;
    bits := 0;
    savedPos := gBitPos;
    for i := 0 to codelen - 1 do
    begin
      bits := bits or (((gData[savedPos div 8] shr (savedPos mod 8)) and 1) shl i);
      savedPos := savedPos + 1;
    end;
    for i := 0 to ht.nSlow - 1 do
      if (ht.slowLen[i] = codelen) and (ht.slowCode[i] = LongWord(bits)) then
      begin
        gBitPos := gBitPos + codelen;
        Result := ht.slowSym[i];
        Exit;
      end;
  end;
  gOk := False;
end;

{ ---- fixed Huffman tables ---- }
{ RFC 1951 §3.2.6: pre-defined code lengths. }

procedure BuildFixed(var litHT: THuffTable; var distHT: THuffTable);
var lens: array[0..287] of Integer; i: Integer;
    dlens: array[0..31] of Integer;
begin
  { literal/length: 0..143=8, 144..255=9, 256..279=7, 280..287=8 }
  for i := 0 to 143  do lens[i] := 8;
  for i := 144 to 255 do lens[i] := 9;
  for i := 256 to 279 do lens[i] := 7;
  for i := 280 to 287 do lens[i] := 8;
  HuffBuild(litHT, lens, 0, 288);

  { distance: all 5 bits }
  for i := 0 to 31 do dlens[i] := 5;
  HuffBuild(distHT, dlens, 0, 32);
end;

{ ---- length/distance tables ---- }

const
  LEN_BASE: array[0..28] of Integer = (
    3, 4, 5, 6, 7, 8, 9, 10, 11, 13, 15, 17, 19, 23, 27, 31,
    35, 43, 51, 59, 67, 83, 99, 115, 131, 163, 195, 227, 258);
  LEN_EXTRA: array[0..28] of Integer = (
    0, 0, 0, 0, 0, 0, 0, 0, 1, 1, 1, 1, 2, 2, 2, 2,
    3, 3, 3, 3, 4, 4, 4, 4, 5, 5, 5, 5, 0);
  DIST_BASE: array[0..29] of Integer = (
    1, 2, 3, 4, 5, 7, 9, 13, 17, 25, 33, 49, 65, 97, 129, 193,
    257, 385, 513, 769, 1025, 1537, 2049, 3073, 4097, 6145, 8193,
    12289, 16385, 24577);
  DIST_EXTRA: array[0..29] of Integer = (
    0, 0, 0, 0, 1, 1, 2, 2, 3, 3, 4, 4, 5, 5, 6, 6,
    7, 7, 8, 8, 9, 9, 10, 10, 11, 11, 12, 12, 13, 13);

{ ---- code-length alphabet order (RFC 1951 §3.2.7) ---- }

const
  CLCL_ORDER: array[0..18] of Integer = (
    16, 17, 18, 0, 8, 7, 9, 6, 10, 5, 11, 4, 12, 3, 13, 2, 14, 1, 15);

{ ---- inflate one block ---- }

function InflateBlock(const litHT, distHT: THuffTable;
                      var err: AnsiString): Boolean;
var sym, lenCode, distCode, copyLen, copyDist, extra, i, back: Integer;
begin
  Result := False;
  repeat
    sym := HuffDecode(litHT);
    if not gOk then begin err := 'truncated huffman data'; Exit; end;
    if sym = INVALID_SYM then begin err := 'bad huffman symbol'; Exit; end;
    if sym < 256 then
      DstAppend(sym)
    else if sym = 256 then
      Break  { end of block }
    else
    begin
      { length }
      lenCode := sym - 257;
      if (lenCode < 0) or (lenCode > 28) then
        begin err := 'bad length code'; Exit; end;
      copyLen := LEN_BASE[lenCode];
      extra   := LEN_EXTRA[lenCode];
      if extra > 0 then
        copyLen := copyLen + ReadBits(extra);
      if not gOk then begin err := 'truncated length extra'; Exit; end;

      { distance }
      distCode := HuffDecode(distHT);
      if not gOk then begin err := 'truncated distance'; Exit; end;
      if (distCode < 0) or (distCode > 29) then
        begin err := 'bad distance code'; Exit; end;
      copyDist := DIST_BASE[distCode];
      extra    := DIST_EXTRA[distCode];
      if extra > 0 then
        copyDist := copyDist + ReadBits(extra);
      if not gOk then begin err := 'truncated distance extra'; Exit; end;

      { copy from window }
      back := gDLen - copyDist;
      if back < 0 then begin err := 'distance beyond output'; Exit; end;
      for i := 0 to copyLen - 1 do
        DstAppend(gDst[back + i]);
    end;
  until False;
  Result := True;
end;

{ ---- dynamic block header ---- }

function InflateDynamic(var litHT, distHT: THuffTable;
                        var err: AnsiString): Boolean;
var hlit, hdist, hclen, i, sym, rep, prev, extra: Integer;
    clLens: array[0..18] of Integer;
    clHT:   THuffTable;
    allLens: array[0..319] of Integer;
    total:  Integer;
begin
  Result := False;
  hlit  := ReadBits(5) + 257;
  hdist := ReadBits(5) + 1;
  hclen := ReadBits(4) + 4;
  if not gOk then begin err := 'truncated dynamic header'; Exit; end;

  { code-length code lengths }
  for i := 0 to 18 do clLens[i] := 0;
  for i := 0 to hclen - 1 do
    clLens[CLCL_ORDER[i]] := ReadBits(3);
  if not gOk then begin err := 'truncated clcl'; Exit; end;
  HuffBuild(clHT, clLens, 0, 19);

  { decode literal/length + distance code lengths }
  total := hlit + hdist;
  for i := 0 to total - 1 do allLens[i] := 0;
  i := 0;
  prev := 0;
  while i < total do
  begin
    sym := HuffDecode(clHT);
    if not gOk then begin err := 'bad clcl symbol'; Exit; end;
    if sym < 16 then
    begin
      allLens[i] := sym;
      prev := sym;
      i := i + 1;
    end
    else if sym = 16 then
    begin
      extra := ReadBits(2) + 3;
      if not gOk then begin err := 'bad rep16'; Exit; end;
      rep := 0;
      while rep < extra do
      begin
        if i >= total then begin err := 'rep16 overflow'; Exit; end;
        allLens[i] := prev;
        i := i + 1;
        rep := rep + 1;
      end;
    end
    else if sym = 17 then
    begin
      extra := ReadBits(3) + 3;
      if not gOk then begin err := 'bad rep17'; Exit; end;
      rep := 0;
      while rep < extra do
      begin
        if i >= total then begin err := 'rep17 overflow'; Exit; end;
        allLens[i] := 0;
        i := i + 1;
        rep := rep + 1;
      end;
      prev := 0;
    end
    else if sym = 18 then
    begin
      extra := ReadBits(7) + 11;
      if not gOk then begin err := 'bad rep18'; Exit; end;
      rep := 0;
      while rep < extra do
      begin
        if i >= total then begin err := 'rep18 overflow'; Exit; end;
        allLens[i] := 0;
        i := i + 1;
        rep := rep + 1;
      end;
      prev := 0;
    end
    else
    begin
      err := 'bad clcl code';
      Exit;
    end;
  end;

  HuffBuild(litHT,  allLens, 0,   hlit);
  HuffBuild(distHT, allLens, hlit, hdist);
  Result := True;
end;

{ ---- stored block ---- }

function InflateStored(var err: AnsiString): Boolean;
var len, nlen, i: Integer;
begin
  Result := False;
  ByteAlign;

  if BytePos + 4 > Length(gData) - 4 then
    begin err := 'truncated stored header'; Exit; end;
  len  := ReadBits(16);
  nlen := ReadBits(16);
  if not gOk then begin err := 'truncated stored header'; Exit; end;
  if nlen <> (65535 - len) then
    begin err := 'bad stored block nlen'; Exit; end;

  if BytePos + len > Length(gData) - 4 then
    begin err := 'truncated stored data'; Exit; end;
  for i := 0 to len - 1 do
    DstAppend(ReadBits(8));
  Result := True;
end;

{ ---- top-level inflate ---- }

function InflateRaw(var err: AnsiString): Boolean;
var bfinal, btype: Integer;
    litHT, distHT: THuffTable;
begin
  Result := False;
  repeat
    bfinal := ReadBits(1);
    btype  := ReadBits(2);
    if not gOk then begin err := 'truncated deflate header'; Exit; end;

    if btype = 0 then
    begin
      if not InflateStored(err) then Exit;
    end
    else if btype = 1 then
    begin
      BuildFixed(litHT, distHT);
      if not InflateBlock(litHT, distHT, err) then Exit;
    end
    else if btype = 2 then
    begin
      if not InflateDynamic(litHT, distHT, err) then Exit;
      if not InflateBlock(litHT, distHT, err) then Exit;
    end
    else
    begin
      err := 'reserved deflate block type';
      Exit;
    end;
  until bfinal <> 0;
  Result := True;
end;

{ ---- public InflateZlib ---- }

function InflateZlib(const src: TByteArray; var dst: TByteArray;
                     var err: AnsiString): Boolean;
var endPos: Integer; wantAdler, gotAdler: LongWord;
    i: Integer;
begin
  Result := False;
  err    := '';
  SetLength(dst, 0);

  if Length(src) < 6 then begin err := 'zlib stream too short'; Exit; end;
  if ((Integer(src[0]) * 256 + Integer(src[1])) mod 31) <> 0 then
    begin err := 'bad zlib header checksum'; Exit; end;
  if (src[0] and $0F) <> 8 then
    begin err := 'unsupported zlib CM (not deflate)'; Exit; end;
  if (src[1] and $20) <> 0 then
    begin err := 'zlib preset dictionary not supported'; Exit; end;

  gData   := src;
  gBitPos := 16;
  gOk     := True;
  gDLen   := 0;
  SetLength(gDst, 256);

  if not InflateRaw(err) then
  begin
    SetLength(gDst, 0);
    Exit;
  end;

  DstTrim;

  { Adler32 trailer: 4 bytes big-endian at the next byte boundary after the
    last deflate block. Discard any partial padding bits. }
  ByteAlign;
  endPos := BytePos;
  if endPos + 4 <> Length(src) then
    begin err := 'trailing zlib data'; SetLength(gDst, 0); Exit; end;

  wantAdler := (LongWord(src[endPos]) shl 24) or
               (LongWord(src[endPos + 1]) shl 16) or
               (LongWord(src[endPos + 2]) shl 8) or
               LongWord(src[endPos + 3]);
  gotAdler := Adler32(gDst);
  if wantAdler <> gotAdler then
    begin err := 'bad adler32'; SetLength(gDst, 0); Exit; end;

  { copy global buffer to caller's dst }
  SetLength(dst, gDLen);
  for i := 0 to gDLen - 1 do
    dst[i] := gDst[i];
  SetLength(gDst, 0);

  Result := True;
end;

{ ---- DeflateZlibStored ---- }

procedure DeflateZlibStored(const src: TByteArray; var dst: TByteArray);
var srcLen, nBlocks, blockLen, pos, i, n: Integer;
    ad: LongWord;
begin
  srcLen  := Length(src);
  nBlocks := (srcLen + 65534) div 65535;
  if nBlocks = 0 then nBlocks := 1;
  { 2 header + nBlocks*(1+4) + srcLen + 4 adler }
  SetLength(gDefDst, 2 + nBlocks * 5 + srcLen + 4);
  n := 0;

  gDefDst[n] := $78; n := n + 1;  { CMF: deflate, window 32K }
  gDefDst[n] := $01; n := n + 1;  { FLG: no dict, level 0 }

  pos := 0;
  repeat
    blockLen := srcLen - pos;
    if blockLen > 65535 then blockLen := 65535;
    if pos + blockLen >= srcLen then
      gDefDst[n] := 1
    else
      gDefDst[n] := 0;
    n := n + 1;

    gDefDst[n] := Byte(blockLen and $FF);         n := n + 1;
    gDefDst[n] := Byte((blockLen shr 8) and $FF); n := n + 1;
    gDefDst[n] := Byte((65535 - blockLen) and $FF);         n := n + 1;
    gDefDst[n] := Byte(((65535 - blockLen) shr 8) and $FF); n := n + 1;

    for i := 0 to blockLen - 1 do
    begin
      gDefDst[n] := src[pos + i];
      n := n + 1;
    end;
    pos := pos + blockLen;
  until pos >= srcLen;

  ad := Adler32(src);
  gDefDst[n] := Byte((ad shr 24) and $FF); n := n + 1;
  gDefDst[n] := Byte((ad shr 16) and $FF); n := n + 1;
  gDefDst[n] := Byte((ad shr 8) and $FF);  n := n + 1;
  gDefDst[n] := Byte(ad and $FF);          n := n + 1;
  SetLength(gDefDst, n);

  { copy global buffer to caller's dst }
  SetLength(dst, n);
  for i := 0 to n - 1 do
    dst[i] := gDefDst[i];
  SetLength(gDefDst, 0);
end;

end.
