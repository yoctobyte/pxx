{ SPDX-License-Identifier: Zlib }
unit zlib;
{$MODE PXX}   { our dialect; the FPC-parity strict-* flags do not judge this file }
{ zlib/deflate inflate (RFC 1950 / RFC 1951).

  Supports all three deflate block types:
    btype=0  stored (uncompressed)
    btype=1  fixed Huffman codes
    btype=2  dynamic Huffman codes

  Entry points:
    InflateZlib(input, output, error) — unwrap zlib header, inflate all blocks,
      verify Adler32. Returns True on success.
    DeflateZlibStored(input, output) — wrap input in a zlib stream using only
      uncompressed deflate blocks (valid zlib, trivial compression).

  AND THIS UNIT IS ALSO PYTHON'S `zlib` MODULE, which is why it is named in
  PyRtlUnitServesPython (pasparser_proc.inc). That list asks whether a unit was
  WRITTEN TO BE the Python module of its name and says each unit's header answers
  it — so the answer is recorded here rather than left to be inferred from the
  Pascal prose above, which describes only half of what the unit is. base64.pas is
  the same arrangement. See the Python surface in the interface below. }

interface

{ pylib for the Python spellings below: `zlib.crc32(b)` takes BYTES, and reading a
  TPyBytes needs the NilPy runtime -- the same seam base64.pas opened, ruled in by
  decide-pcl-may-use-pylib. Pascal callers of InflateZlib never touch it.
  COST, since it is not free: png.pas `uses zlib`, so pylib enters png's closure
  too. That is the price of one unit carrying both surfaces, which is the house
  pattern (pxx-crash-course.md) rather than a mimic_zlib competing for the name. }
uses hashing, pylib;

function InflateZlib(const src: TByteArray; var dst: TByteArray;
                     var err: AnsiString): Boolean;

{ InflateGzip(input, output, error) — parse an RFC 1952 gzip member (magic,
  optional FEXTRA/FNAME/FCOMMENT/FHCRC fields), inflate the raw deflate body, and
  verify the CRC32 + ISIZE trailer. Returns True on success. }
function InflateGzip(const src: TByteArray; var dst: TByteArray;
                     var err: AnsiString): Boolean;

{ InflateRawBytes(input, output, error) — inflate a bare RFC 1951 deflate stream
  (no zlib/gzip wrapper, no trailing checksum). For HTTP `Content-Encoding:
  deflate` peers that send raw deflate rather than zlib-wrapped. }
function InflateRawBytes(const src: TByteArray; var dst: TByteArray;
                         var err: AnsiString): Boolean;

procedure DeflateZlibStored(const src: TByteArray; var dst: TByteArray);

{ ---- Python's `zlib` module surface ------------------------------------------

  `import zlib` already resolved to this unit before these existed, so the wall a
  NilPy program hit was `no member crc32 came of the qualifier zlib` -- a MISSING
  MEMBER on a module that was otherwise found. Both checksums were already here in
  `hashing`; only the Python spelling was absent.

  RETURNS Int64, NOT LongWord, and that is the whole point of the signature.
  CPython's zlib.crc32 returns an UNSIGNED int, so every value above 2^31 has to
  survive the trip. An Int64 holds the unsigned 32-bit range exactly and cannot be
  printed as a negative number; a LongWord return would be right or wrong
  depending on how the frontend marshals an unsigned, and the failure would show
  up only for inputs whose checksum happens to set the top bit -- which a hello
  world test never produces.

  `value` is CPython's running-checksum argument, for callers that feed data in
  chunks. The defaults are CPython's own: 0 for crc32, 1 for adler32. A DEFAULT
  PARAMETER rather than two overloads, deliberately: NilPy resolves overloads by
  NAME and ignores argument type, so the two-overload spelling silently runs the
  wrong body (mimic_array.pas:89, bug-n-an-overloaded-constructor-is-picked-by-
  name-ignoring-argument-type).

  STILL NOT IMPLEMENTED, stated rather than left to be discovered:
  `compressobj`, `decompressobj` (the incremental objects) and the `Z_*`
  constants. No program has asked for them. }
function crc32(const data: Variant; const value: Variant = 0): Int64;

{ NAME COLLISION, DELIBERATE AND DOCUMENTED: `adler32` differs from
  hashing.Adler32 ONLY IN CASE, and PXX is case-insensitive. So in any unit whose
  uses clause names both, `Adler32(someByteArray)` binds to THIS one, converts the
  array to a Variant, and returns a checksum of its string rendering -- no
  diagnostic, a plausible wrong number. Inside this unit the shadowing is
  unconditional, which is why both internal call sites are spelled
  `hashing.Adler32`. The Python spelling cannot be renamed: `zlib.adler32` is the
  call an application writes. If you add a consumer that uses hashing AND zlib,
  qualify. }
function adler32(const data: Variant; const value: Variant = 1): Int64;

{ `zlib.compress(data, level=-1)` -> bytes, and `zlib.decompress(data)` -> bytes.

  COMPRESS DOES NOT COMPRESS, AND THE OUTPUT IS STILL CORRECT. It wraps the input
  in a valid RFC 1950 stream built from STORED deflate blocks, so every
  decompressor reads it and the bytes that come back out are the bytes that went
  in -- it is simply larger than CPython's. That is the test CLAUDE.md sets for
  FPC and it is the right one here: the VALUE round-trips, the intermediate
  encoding is implementation latitude. A byte-diff of compress() against CPython
  DIFFERS BY DESIGN and is not a defect to file.

  This is not a shortcut taken for the shim's convenience -- it is what our own
  PNG writer already does. png.pas:169 builds its IDAT with the same
  DeflateZlibStored call, and the wall that prompted these members is
  lekkerzeilen's capture.py writing a PNG screenshot: `zlib.compress(raw, 6)` for
  the IDAT and `zlib.crc32(tag + payload)` for the chunk CRC. A real deflate
  encoder is a separate piece of work, and when one lands both callers get it.

  `level` is ACCEPTED AND IGNORED, which is honest for a stored-block encoder:
  every level produces the same valid stream. Refusing a level would break the
  call that motivated this for no gain. }
type
  { CPython raises `zlib.error`. Spelled to match, so `except zlib.error:` in an
    application binds here. }
  error = class(Exception) end;

function compress(const data: Variant; const level: Variant = -1): TPyBytes;
function decompress(const data: Variant): TPyBytes;

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
  { HOW MANY TRAILING BYTES OF gData ARE A CHECKSUM AND NOT DEFLATE DATA.
    InflateStored used the literal 4 for this, which is right for zlib, WRONG for
    a raw RFC 1951 stream (no trailer at all) and wrong for gzip (CRC32 + ISIZE =
    8). The raw case is the one that broke: a valid stored-block stream was
    rejected as `truncated stored data` because the reader believed its last four
    bytes were a checksum it must not consume. Each entry point now states its own
    trailer, so the bound is a fact about the stream rather than a constant that
    happens to suit one of three callers. }
  gTrailer: Integer;

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

  if BytePos + 4 > Length(gData) - gTrailer then
    begin err := 'truncated stored header'; Exit; end;
  len  := ReadBits(16);
  nlen := ReadBits(16);
  if not gOk then begin err := 'truncated stored header'; Exit; end;
  if nlen <> (65535 - len) then
    begin err := 'bad stored block nlen'; Exit; end;

  if BytePos + len > Length(gData) - gTrailer then
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
  gTrailer := 4;            { zlib: Adler32 }
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
  { hashing.Adler32 QUALIFIED, and it must stay qualified. This unit now declares
    a Python-surface `adler32(Variant)` of its own, PXX is case-insensitive, and a
    unit's own declaration shadows an imported one -- so a bare `Adler32(gDst)`
    here silently called the Variant shim, marshalled a TByteArray through
    pystr_of, and produced a checksum of garbage. Measured: the writer and the
    reader both did it, disagreed, and the round trip failed with `bad adler32`
    while the decoded BYTES were provably correct. }
  gotAdler := hashing.Adler32(gDst);
  if wantAdler <> gotAdler then
    begin err := 'bad adler32'; SetLength(gDst, 0); Exit; end;

  { copy global buffer to caller's dst }
  SetLength(dst, gDLen);
  for i := 0 to gDLen - 1 do
    dst[i] := gDst[i];
  SetLength(gDst, 0);

  Result := True;
end;

{ ---- public InflateGzip ---- }

function InflateGzip(const src: TByteArray; var dst: TByteArray;
                     var err: AnsiString): Boolean;
var flg, hdr, endPos, i: Integer; xlen: Integer;
    wantCrc, gotCrc, wantSize: LongWord;
begin
  Result := False;
  err    := '';
  SetLength(dst, 0);

  if Length(src) < 18 then begin err := 'gzip stream too short'; Exit; end;
  if (src[0] <> $1F) or (src[1] <> $8B) then
    begin err := 'bad gzip magic'; Exit; end;
  if src[2] <> 8 then
    begin err := 'unsupported gzip CM (not deflate)'; Exit; end;

  flg := Integer(src[3]);
  hdr := 10;                              { fixed header: magic..OS }

  if (flg and $04) <> 0 then              { FEXTRA: XLEN (LE) + that many bytes }
  begin
    if hdr + 2 > Length(src) then begin err := 'truncated gzip FEXTRA'; Exit; end;
    xlen := Integer(src[hdr]) or (Integer(src[hdr + 1]) shl 8);
    hdr := hdr + 2 + xlen;
  end;
  if (flg and $08) <> 0 then              { FNAME: zero-terminated }
  begin
    while (hdr < Length(src)) and (src[hdr] <> 0) do Inc(hdr);
    Inc(hdr);
  end;
  if (flg and $10) <> 0 then              { FCOMMENT: zero-terminated }
  begin
    while (hdr < Length(src)) and (src[hdr] <> 0) do Inc(hdr);
    Inc(hdr);
  end;
  if (flg and $02) <> 0 then hdr := hdr + 2;   { FHCRC: 2-byte header CRC }

  if hdr + 8 > Length(src) then begin err := 'truncated gzip header'; Exit; end;

  gData   := src;
  gBitPos := hdr * 8;
  gTrailer := 8;            { gzip: CRC32 + ISIZE, per RFC 1952 -- EIGHT, and the
                              literal this replaced said 4, so the gzip bound was
                              four bytes too permissive. A stored block could
                              claim part of its own trailer; the CRC check then
                              failed, which is why it never showed as truncation. }
  gOk     := True;
  gDLen   := 0;
  SetLength(gDst, 256);

  if not InflateRaw(err) then begin SetLength(gDst, 0); Exit; end;
  DstTrim;

  { trailer: CRC32 then ISIZE, each 4 bytes little-endian, byte-aligned. }
  ByteAlign;
  endPos := BytePos;
  if endPos + 8 <> Length(src) then
    begin err := 'trailing gzip data'; SetLength(gDst, 0); Exit; end;

  wantCrc := LongWord(src[endPos]) or (LongWord(src[endPos + 1]) shl 8) or
             (LongWord(src[endPos + 2]) shl 16) or (LongWord(src[endPos + 3]) shl 24);
  wantSize := LongWord(src[endPos + 4]) or (LongWord(src[endPos + 5]) shl 8) or
              (LongWord(src[endPos + 6]) shl 16) or (LongWord(src[endPos + 7]) shl 24);

  { copy global buffer to caller's dst }
  SetLength(dst, gDLen);
  for i := 0 to gDLen - 1 do
    dst[i] := gDst[i];
  SetLength(gDst, 0);

  gotCrc := CRC32Bytes(dst);
  if gotCrc <> wantCrc then
    begin err := 'bad gzip crc32'; SetLength(dst, 0); Exit; end;
  if wantSize <> LongWord(gDLen) then
    begin err := 'bad gzip isize'; SetLength(dst, 0); Exit; end;

  Result := True;
end;

{ ---- public InflateRawBytes ---- }

function InflateRawBytes(const src: TByteArray; var dst: TByteArray;
                         var err: AnsiString): Boolean;
var i: Integer;
begin
  Result := False;
  err    := '';
  SetLength(dst, 0);
  if Length(src) < 1 then begin err := 'empty deflate stream'; Exit; end;

  gData   := src;
  gBitPos := 0;
  gTrailer := 0;            { raw RFC 1951: no trailer }
  gOk     := True;
  gDLen   := 0;
  SetLength(gDst, 256);

  if not InflateRaw(err) then begin SetLength(gDst, 0); Exit; end;
  DstTrim;

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

  ad := hashing.Adler32(src);   { qualified -- see the note in InflateZlib }
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


{ ---- Python `zlib` surface ---------------------------------------------------- }

{ bytes (TPyBytes) or a plain string -- an application may hand over either.
  CPython REFUSES a str here; accepting one is deliberate, because NilPy is
  upward compatible with CPython in one direction and accepting what CPython
  rejects is a feature (nilpy-semantics-divergences.md).
  `pyvar_is_objtag` rather than an open-coded `pyvartag(data) = 7`: pylib's own
  comment at the declaration says copying the tag ENCODING into a lib/rtl unit
  makes a second copy that stays wrong when the encoding moves. }
function PyBytesToArray(const data: Variant): TByteArray;
var o: TObject; by: TPyBytes; raw: AnsiString; i: Integer;
begin
  o := nil;
  if pyvar_is_objtag(data) then o := TObject(pyvarobj(data));
  if (o <> nil) and (o is TPyBytes) then
  begin
    { `o is TPyBytes` rather than an unchecked cast of anything obj-tagged --
      DataToString in mimic_urllib_request.pas is the model, and the difference
      matters for `zlib.crc32(some_list)`: the cast would read a length off
      whatever object arrived. }
    by := TPyBytes(o);
    SetLength(Result, by.count);
    for i := 0 to by.count - 1 do
      Result[i] := by.at(i);
    Exit;
  end;
  { bytes OR a plain string -- an application may hand over either. CPython
    REFUSES a str here; accepting one is deliberate, because NilPy is upward
    compatible with CPython in one direction and accepting what CPython rejects
    is a feature (nilpy-semantics-divergences.md). }
  raw := pystr_of(data);
  SetLength(Result, Length(raw));
  for i := 1 to Length(raw) do
    Result[i - 1] := Byte(raw[i]);
end;

{ THE DECLARED DEFAULT IS NOT APPLIED ON THE NilPy CALL PATH, MEASURED, so this
  absence test is load-bearing rather than defensive. At arity 1 an omitted
  `value` arrives as pynone -- `pyvartag` 0, `pyvar_to_int` 0 -- and NOT as the
  declared 0 or 1. The declaration keeps its default anyway, because that is the
  correct Pascal signature and the test is harmless once the frontend honours it:
  bug-n-a-pascal-default-parameter-is-ignored-when-the-call-comes-from-nilpy.

  AND THIS IS WHY adler32 FOUND IT AND crc32 COULD NOT. crc32's CPython default
  is 0, which is exactly the value an unsupplied argument already reads as, so
  all four crc32 rows matched the oracle while the mechanism was broken --
  the failure value collided with the expected one. adler32's default is 1, so
  its `a` accumulator started at 0 and every row was wrong by a visible amount.
  A probe whose right answer differs from the do-nothing answer is the only kind
  that can see this class at all. }
function ChecksumSeed(const value: Variant; whenAbsent: LongWord): LongWord;
begin
  if value = pynone then
    Result := whenAbsent
  else
    Result := LongWord(pyvar_to_int(value));
end;

function crc32(const data: Variant; const value: Variant = 0): Int64;
var crc: LongWord; b: TByteArray; i: Integer;
begin
  b := PyBytesToArray(data);
  { THE CONTINUATION HAS TO UNDO CRC32Final's XOR, and getting this backwards
    produces a checksum that is correct for every ONE-SHOT caller and wrong only
    for a chunked one -- so a `crc32(b'abc')` test cannot see the mistake.
    CRC32Init is $FFFFFFFF and CRC32Final xors with $FFFFFFFF, so the externally
    visible value v corresponds to the internal register v xor $FFFFFFFF. With
    CPython's default v=0 that is exactly CRC32Init, which is the check that the
    two conventions have been lined up rather than merely assumed. }
  crc := ChecksumSeed(value, 0) xor LongWord($FFFFFFFF);
  for i := 0 to Length(b) - 1 do
    crc := CRC32Update(crc, b[i]);
  Result := Int64(CRC32Final(crc));
end;

function adler32(const data: Variant; const value: Variant = 1): Int64;
var a, bsum, v: LongWord; b: TByteArray; i: Integer;
begin
  b := PyBytesToArray(data);
  { Adler32 keeps two accumulators packed as (b shl 16) or a, so a continuation
    unpacks the incoming value rather than reinitialising. CPython's default 1 is
    a=1, b=0 -- hashing.Adler32's own starting state. }
  v    := ChecksumSeed(value, 1);
  a    := v and $FFFF;
  bsum := (v shr 16) and $FFFF;
  for i := 0 to Length(b) - 1 do
  begin
    a    := (a + LongWord(b[i])) mod ADLER_MOD;
    bsum := (bsum + a) mod ADLER_MOD;
  end;
  Result := Int64((bsum shl 16) or a);
end;

{ TPyBytes rather than base64.pas's AnsiString-with-a-stated-divergence: these
  two feed binary file writes and byte concatenation (`tag + payload`), where a
  string would have to survive a round trip through text. Returning real bytes
  costs one loop. }
function ArrayToPyBytes(const a: TByteArray): TPyBytes;
var i: Integer;
begin
  Result := TPyBytes.Create(Length(a));
  for i := 0 to Length(a) - 1 do
    Result.put(i, a[i]);
end;

function compress(const data: Variant; const level: Variant = -1): TPyBytes;
var src, dst: TByteArray;
begin
  src := PyBytesToArray(data);
  DeflateZlibStored(src, dst);
  Result := ArrayToPyBytes(dst);
end;

function decompress(const data: Variant): TPyBytes;
var src, dst: TByteArray; err: AnsiString;
begin
  src := PyBytesToArray(data);
  err := '';
  if not InflateZlib(src, dst, err) then
    raise error.Create('zlib.error: ' + err);
  Result := ArrayToPyBytes(dst);
end;

end.
