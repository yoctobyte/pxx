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
      uncompressed deflate blocks (valid zlib, trivial compression). Still the
      level-0 path, and still what a caller wanting no compression should ask
      for by name.
    DeflateZlib(input, output, level) — the compressing encoder: LZ77 + fixed
      Huffman (btype=1). This is what `zlib.compress` and png.pas use.

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

{ DeflateZlib(input, output, level) -- a real compressing encoder: LZ77 with a
  hash-chain match finder, emitted as one fixed-Huffman (btype=1) block. `level`
  is 0..9 or -1 for the default 6, and it SELECTS WORK rather than being
  accepted and dropped: 0 routes to the stored writer above (which is what level
  0 means to CPython), 1-3 match greedily, 4-9 add lazy matching, and the search
  bounds widen with the number. Every level emits a valid stream; higher ones
  spend longer looking for matches. }
procedure DeflateZlib(const src: TByteArray; var dst: TByteArray; level: Integer);

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
  constants. No program has asked for them — but ZLIB_VERSION now has one, see
  below. }

{ `zlib.ZLIB_VERSION`. CPython's names the libz it was BUILT AGAINST; there is no
  libz here, this unit is a from-scratch RFC 1950 / 1951 implementation, so any
  `1.2.x` answer would be a false claim about provenance.

  It reports US instead, and the program that asked settles the question rather
  than taste: lekkerzeilen/__main__.py:141 prints `"zlib %s" % zlib.ZLIB_VERSION`
  immediately above its own explanation that its `file` column "matches only where
  the same zlib is underneath -- deflate may encode the same bytes several valid
  ways, so a differing `file` column is not a fault." The line exists to say WHICH
  zlib produced the bytes. A spoofed libz version would not merely be untrue, it
  would defeat the one purpose the caller has for it, and send a reader comparing
  columns looking for a bug that is not there.

  THE COST, because it is real: a program doing version arithmetic
  (`tuple(map(int, zlib.ZLIB_VERSION.split('.')))`) raises here where CPython
  returns numbers. That is the better of the two failure directions — loudly wrong
  beats quietly misidentified — and it is the same call sys.version makes, which
  raises AttributeError rather than inventing a Python version. Revisit if a real
  program turns out to compare it. }
const
  ZLIB_VERSION = 'pxx-rtl';
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

  COMPRESS NOW COMPRESSES. Until 2026-09-13 it wrapped the input in STORED
  deflate blocks -- valid RFC 1950, correct on the round trip, and simply larger
  than CPython's. It goes through DeflateZlib now: LZ77 with a hash-chain match
  finder in one fixed-Huffman block. The caller that paid for the old behaviour
  was lekkerzeilen's capture.py writing PNG screenshots (`zlib.compress(raw, 6)`
  for the IDAT, `zlib.crc32(tag + payload)` for the chunk CRC), whose six
  --conform PNGs came out 3-12x larger than CPython's. png.pas builds its IDAT
  through the same encoder, so both callers got it at once, which is what the
  old note here predicted would happen.

  A BYTE-DIFF AGAINST CPYTHON STILL DIFFERS BY DESIGN and is still not a defect
  to file. Our sizes are now close to CPython's rather than multiples of them,
  but deflate does not have one right answer: which matches an encoder finds is
  latitude, and CPython emits dynamic-Huffman blocks where we emit fixed. The
  test CLAUDE.md sets is the one that applies -- the VALUE round-trips, and the
  intermediate encoding is ours. What IS assertable, and is asserted in
  test/lib_zlib.pas, is that CPython's decompressor reads our stream.

  `level` SELECTS WORK rather than being accepted and dropped -- see the
  DeflateZlib comment above. It stopped being honest to ignore it the moment
  the levels could differ. }
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


{ ---- DeflateZlib: a real encoder (fixed Huffman, btype=1) --------------------

  WHY THIS EXISTS AT ALL, since DeflateZlibStored above is valid zlib and was a
  deliberate choice: stored blocks never compress, and the cost stopped being
  theoretical. lekkerzeilen's capture.py writes PNG screenshots through
  `zlib.compress`, and every one of its six --conform PNGs came out 3-12x larger
  than CPython's (flat grey 8x8: 268 bytes against 72). 2000 identical bytes went
  out as 2011. The streams were always correct -- this was a capability gap, never
  a correctness bug, which is why it could sit here behind a comment.

  FIXED HUFFMAN AND NOT DYNAMIC, deliberately. btype=1 needs no code-length
  alphabet emission, so it is a few hundred lines rather than a thousand, and on
  repetitive input it gets nearly all of the win: 2000 identical bytes become
  eight len-258/dist-1 matches at ~13 bits each. btype=2 would beat it on
  literal-heavy input (photographic pixel data, text) by fitting the code lengths
  to the actual symbol frequencies. That is a separate landing with its own
  measurement, not a TODO here.

  THE DECODER IN THIS UNIT IS THE ORACLE THAT KEEPS THIS HONEST. InflateBlock
  already reads fixed-Huffman blocks and predates this encoder, so a round trip
  through our own code exercises two independently-written halves. It is still
  not sufficient on its own -- a shared misreading of the RFC would pass both
  ways -- so test/lib_zlib.pas also asserts against streams CPython produced, and
  lib-test diffs our output through CPython's zlib.decompress when python3 is
  present. }

const
  DEF_HASH_SIZE = 32768;
  DEF_HASH_MASK = 32767;
  DEF_MIN_MATCH = 3;
  DEF_MAX_MATCH = 258;
  DEF_MAX_DIST  = 32768;

var
  { Module globals for the same reason the inflate state above is module-global:
    the note at gData explains that dynamic arrays through several parameter
    layers are a sore spot. Not reentrant, which matches the rest of the unit. }
  gDefN:      Integer;        { bytes written into gDefDst }
  gBitBuf:    LongWord;       { pending bits, LSB-first }
  gBitCnt:    Integer;        { how many bits are pending }
  gSrcB:      TByteArray;     { deflate input }
  gSrcLen:    Integer;
  gHashHead:  array of Integer;
  gHashPrev:  array of Integer;
  gMatchLen:  Integer;        { DefFindMatch results }
  gMatchDist: Integer;

procedure DefPutByte(b: Integer);
var newcap: Integer;
begin
  if gDefN >= Length(gDefDst) then
  begin
    newcap := Length(gDefDst) * 2;
    if newcap < 64 then newcap := 64;
    SetLength(gDefDst, newcap);
  end;
  gDefDst[gDefN] := Byte(b and $FF);
  gDefN := gDefN + 1;
end;

{ DEFLATE PACKS BITS LSB-FIRST WITHIN A BYTE, and that is not the order Huffman
  codes are written in -- RFC 1951 s3.1.1 spells out that Huffman codes go
  MSB-of-the-code first while everything else (the extra bits, LEN/NLEN) goes
  LSB-first. So PutBits is the LSB-first primitive and every Huffman code passes
  through RevBits on the way in. Getting this backwards produces a stream that
  decodes to plausible garbage rather than to an error, which is why the tests
  compare against CPython's bytes and not only against our own round trip. }
procedure PutBits(value, n: Integer);
begin
  if n <= 0 then Exit;
  gBitBuf := gBitBuf or (LongWord(value and ((1 shl n) - 1)) shl gBitCnt);
  gBitCnt := gBitCnt + n;
  while gBitCnt >= 8 do
  begin
    DefPutByte(Integer(gBitBuf and $FF));
    gBitBuf := gBitBuf shr 8;
    gBitCnt := gBitCnt - 8;
  end;
end;

procedure FlushBits;
begin
  if gBitCnt > 0 then
    DefPutByte(Integer(gBitBuf and $FF));
  gBitBuf := 0;
  gBitCnt := 0;
end;

function RevBits(code, n: Integer): Integer;
var i, r: Integer;
begin
  r := 0;
  for i := 0 to n - 1 do
    r := (r shl 1) or ((code shr i) and 1);
  Result := r;
end;

{ Fixed literal/length alphabet, RFC 1951 s3.2.6. Four ranges with three
  different code lengths, which is the whole reason btype=1 costs nothing to
  emit: both ends already know this table. }
procedure PutFixedLit(sym: Integer);
begin
  if sym <= 143 then
    PutBits(RevBits($30 + sym, 8), 8)
  else if sym <= 255 then
    PutBits(RevBits($190 + sym - 144, 9), 9)
  else if sym <= 279 then
    PutBits(RevBits(sym - 256, 7), 7)
  else
    PutBits(RevBits($C0 + sym - 280, 8), 8);
end;

{ Emit one <length, distance> pair. The LEN_BASE/LEN_EXTRA/DIST_BASE/DIST_EXTRA
  tables are the inflater's, shared rather than copied -- a second copy of these
  is exactly the shape normalise-dont-special-case.md warns about, and the arm
  that stays broken would be this one, since the decoder is exercised far more. }
procedure PutMatch(len, dist: Integer);
var idx, didx: Integer;
begin
  idx := 28;
  while (idx > 0) and (LEN_BASE[idx] > len) do idx := idx - 1;
  PutFixedLit(257 + idx);
  PutBits(len - LEN_BASE[idx], LEN_EXTRA[idx]);

  didx := 29;
  while (didx > 0) and (DIST_BASE[didx] > dist) do didx := didx - 1;
  PutBits(RevBits(didx, 5), 5);
  PutBits(dist - DIST_BASE[didx], DIST_EXTRA[didx]);
end;

function DefHash(pos: Integer): Integer;
begin
  Result := ((gSrcB[pos] shl 10) xor (gSrcB[pos + 1] shl 5) xor gSrcB[pos + 2])
            and DEF_HASH_MASK;
end;

procedure DefInsert(pos: Integer);
var h: Integer;
begin
  if pos + DEF_MIN_MATCH > gSrcLen then Exit;
  h := DefHash(pos);
  gHashPrev[pos] := gHashHead[h];
  gHashHead[h] := pos;
end;

{ Longest match for the string at `pos`, walking the hash chain newest-first so
  the first acceptable match is also the nearest one (shorter distance code).
  `maxChain` bounds the work and `niceLen` stops early on a match good enough to
  not be worth improving -- those two are what `level` actually selects. }
procedure DefFindMatch(pos, maxChain, niceLen: Integer);
var cur, chain, len, maxLen, limit: Integer;
begin
  gMatchLen := 0;
  gMatchDist := 0;
  if pos + DEF_MIN_MATCH > gSrcLen then Exit;

  maxLen := gSrcLen - pos;
  if maxLen > DEF_MAX_MATCH then maxLen := DEF_MAX_MATCH;
  if maxLen < DEF_MIN_MATCH then Exit;

  limit := pos - DEF_MAX_DIST;
  if limit < 0 then limit := 0;

  cur := gHashHead[DefHash(pos)];
  chain := maxChain;
  while (cur >= limit) and (chain > 0) do
  begin
    { Check the byte that would EXTEND the current best before comparing from
      the start -- a candidate that cannot beat what we hold is rejected in one
      comparison instead of gMatchLen of them. }
    if (gMatchLen = 0) or (gSrcB[cur + gMatchLen] = gSrcB[pos + gMatchLen]) then
    begin
      len := 0;
      while (len < maxLen) and (gSrcB[cur + len] = gSrcB[pos + len]) do
        len := len + 1;
      if len > gMatchLen then
      begin
        gMatchLen := len;
        gMatchDist := pos - cur;
        if len >= niceLen then Break;
      end;
    end;
    cur := gHashPrev[cur];
    chain := chain - 1;
  end;

  if gMatchLen < DEF_MIN_MATCH then
  begin
    gMatchLen := 0;
    gMatchDist := 0;
  end;
end;

{ LZ77 over the whole input, emitted as one fixed-Huffman block.

  LAZY MATCHING (`maxLazy` > 0): having found a match at `pos`, look again at
  pos+1 before committing. If the later match is longer, the byte at `pos` goes
  out as a literal and the longer match wins. It costs one extra search per
  position and is worth several percent on text.

  The `while ins < pos` line is the part that is easy to get wrong: every
  position strictly before `pos` must be in the chains, INCLUDING the ones a
  match jumped over, and they must go in ascending order or the chain stops
  being newest-first. }
procedure DeflateFixedBody(maxChain, niceLen, maxLazy: Integer);
var pos, ins, curLen, curDist, prevLen, prevDist, prevPos: Integer;
    havePrev: Boolean;
begin
  pos := 0;
  ins := 0;
  havePrev := False;
  prevLen := 0; prevDist := 0; prevPos := 0;

  while pos < gSrcLen do
  begin
    while ins < pos do
    begin
      DefInsert(ins);
      ins := ins + 1;
    end;

    DefFindMatch(pos, maxChain, niceLen);
    curLen := gMatchLen;
    curDist := gMatchDist;

    if havePrev then
    begin
      if curLen > prevLen then
      begin
        PutFixedLit(gSrcB[prevPos]);
        prevLen := curLen; prevDist := curDist; prevPos := pos;
        pos := pos + 1;
      end
      else
      begin
        PutMatch(prevLen, prevDist);
        pos := prevPos + prevLen;
        havePrev := False;
      end;
    end
    else if (curLen >= DEF_MIN_MATCH) and (curLen < maxLazy) then
    begin
      prevLen := curLen; prevDist := curDist; prevPos := pos;
      havePrev := True;
      pos := pos + 1;
    end
    else if curLen >= DEF_MIN_MATCH then
    begin
      PutMatch(curLen, curDist);
      pos := pos + curLen;
    end
    else
    begin
      PutFixedLit(gSrcB[pos]);
      pos := pos + 1;
    end;
  end;

  { A deferred match with the input exhausted. Unreachable as the bounds stand
    -- deferring needs prevLen >= 3, which puts pos = prevPos + 1 at least two
    bytes short of the end -- but a future bound change must not turn that into
    silently dropped output. }
  if havePrev then
    PutMatch(prevLen, prevDist);
end;

{ zlib's own level table, simplified to the three knobs this encoder has. Level
  0 is not here: it means STORED to CPython, and routing it to the stored writer
  is the honest reading rather than "the cheapest compression we do". }
procedure DefLevelConfig(level: Integer; var maxChain, niceLen, maxLazy: Integer);
begin
  case level of
    1: begin maxChain :=    4; niceLen :=   8; maxLazy :=   0; end;
    2: begin maxChain :=    8; niceLen :=  16; maxLazy :=   0; end;
    3: begin maxChain :=   32; niceLen :=  32; maxLazy :=   0; end;
    4: begin maxChain :=   16; niceLen :=  16; maxLazy :=   4; end;
    5: begin maxChain :=   32; niceLen :=  32; maxLazy :=   8; end;
    6: begin maxChain :=  128; niceLen := 128; maxLazy :=  16; end;
    7: begin maxChain :=  256; niceLen := 128; maxLazy :=  32; end;
    8: begin maxChain := 1024; niceLen := 258; maxLazy := 128; end;
  else
    begin maxChain := 4096; niceLen := 258; maxLazy := 258; end;
  end;
end;

procedure DeflateZlib(const src: TByteArray; var dst: TByteArray; level: Integer);
var i, cmf, flg, maxChain, niceLen, maxLazy: Integer;
    storedLen, nBlocks: Integer;
    ad: LongWord;
begin
  if level < 0 then level := 6;          { -1 is CPython's "default" }
  if level > 9 then level := 9;
  if level = 0 then
  begin
    DeflateZlibStored(src, dst);
    Exit;
  end;

  { COPIED, not aliased. gSrcB is a module global whose storage this procedure
    frees on the way out; pointing it at the caller's array would make that
    cleanup a question about how the dialect refcounts dynamic arrays, and the
    answer would be invisible until it was wrong. One O(n) copy buys the
    question not being asked. }
  gSrcLen := Length(src);
  SetLength(gSrcB, gSrcLen);
  for i := 0 to gSrcLen - 1 do gSrcB[i] := src[i];
  SetLength(gHashHead, DEF_HASH_SIZE);
  for i := 0 to DEF_HASH_SIZE - 1 do gHashHead[i] := -1;
  SetLength(gHashPrev, gSrcLen);
  for i := 0 to gSrcLen - 1 do gHashPrev[i] := -1;

  nBlocks := (gSrcLen + 65534) div 65535;
  if nBlocks = 0 then nBlocks := 1;

  SetLength(gDefDst, 0);
  gDefN := 0; gBitBuf := 0; gBitCnt := 0;

  { CMF/FLG, RFC 1950 s2.2. FLEVEL carries the level band, and FCHECK is then
    chosen so the 16-bit header is a multiple of 31. Worth matching exactly:
    these are the two bytes a reader sees first, and ours now head `78 9c` at the
    default like CPython's rather than `78 01`. }
  cmf := $78;
  if level <= 1 then flg := 0
  else if level <= 5 then flg := 64
  else if level = 6 then flg := 128
  else flg := 192;
  flg := flg + (31 - ((cmf * 256 + flg) mod 31)) mod 31;
  DefPutByte(cmf);
  DefPutByte(flg);

  PutBits(1, 1);   { BFINAL = 1: one block for the whole input }
  PutBits(1, 2);   { BTYPE  = 01: fixed Huffman }

  DefLevelConfig(level, maxChain, niceLen, maxLazy);
  DeflateFixedBody(maxChain, niceLen, maxLazy);

  PutFixedLit(256);   { end-of-block }
  FlushBits;

  ad := hashing.Adler32(src);   { qualified -- see the note in InflateZlib }
  DefPutByte(Integer((ad shr 24) and $FF));
  DefPutByte(Integer((ad shr 16) and $FF));
  DefPutByte(Integer((ad shr 8) and $FF));
  DefPutByte(Integer(ad and $FF));

  { STORED FALLBACK, and it is not an optimisation -- it is the bound that makes
    this function safe to call on anything. A fixed-Huffman block spends 8 or 9
    bits on every literal, so input with no matches in it (already-compressed
    data, a good PRNG) comes out LARGER than it went in: measured here, 4096
    bytes of LCG output became 4331, and 256 distinct bytes became 278. Stored
    blocks cost 5 bytes per 64KB plus the 6-byte wrapper and cannot expand
    beyond that, so taking whichever is smaller caps the worst case instead of
    leaving a caller to discover it. CPython does the same thing, which is why
    its output never blows up either.

    Compared AFTER emitting rather than predicted: the honest comparison is
    against the bytes we actually produced, and a prediction would be a second
    model of this encoder's output that could drift from it. }
  storedLen := 2 + nBlocks * 5 + gSrcLen + 4;
  if gDefN >= storedLen then
  begin
    SetLength(gDefDst, 0);
    SetLength(gHashHead, 0);
    SetLength(gHashPrev, 0);
    SetLength(gSrcB, 0);
    DeflateZlibStored(src, dst);
    Exit;
  end;

  SetLength(dst, gDefN);
  for i := 0 to gDefN - 1 do
    dst[i] := gDefDst[i];

  SetLength(gDefDst, 0);
  SetLength(gHashHead, 0);
  SetLength(gHashPrev, 0);
  SetLength(gSrcB, 0);
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
  bug-n-a-variant-default-parameter-arrives-as-none-from-nilpy-while-typed-defaults-apply.

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
var src, dst: TByteArray; lv: Integer;
begin
  src := PyBytesToArray(data);
  { An absent level is CPython's -1, which DeflateZlib reads as 6. Spelled
    through pynone rather than defaulted to 6 here so the two spellings of
    "default" stay one value in one place. }
  if level = pynone then
    lv := -1
  else
    lv := Integer(pyvar_to_int(level));
  DeflateZlib(src, dst, lv);
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
