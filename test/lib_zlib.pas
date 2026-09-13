program lib_zlib;
{ Deterministic zlib inflate tests.  Streams are embedded as byte arrays so
  the test has no runtime dependencies beyond the RTL. }

uses hashing, zlib;

var outbuf, enc: TByteArray;
    err: AnsiString;
    good: Boolean;
    bad, i: Integer;

function SameBytes(const a, b: TByteArray): Boolean;
var i: Integer;
begin
  Result := False;
  if Length(a) <> Length(b) then Exit;
  for i := 0 to Length(a) - 1 do
    if a[i] <> b[i] then Exit;
  Result := True;
end;

procedure Fail(const msg: AnsiString);
begin
  writeln('FAIL ', msg);
  bad := 1;
end;

{ sysutils is deliberately NOT in the uses clause -- it declares its own
  TByteArray as a STATIC array, which shadows hashing's dynamic one and makes
  SetLength refuse. So the one thing this file needed from it is spelled here. }
function IStr(v: Integer): AnsiString;
var s: AnsiString; neg: Boolean;
begin
  if v = 0 then begin Result := '0'; Exit; end;
  neg := v < 0;
  if neg then v := -v;
  s := '';
  while v > 0 do
  begin
    s := Chr(48 + (v mod 10)) + s;
    v := v div 10;
  end;
  if neg then s := '-' + s;
  Result := s;
end;

procedure TestStoredRoundtrip;
var src: TByteArray;
    j: Integer;
begin
  SetLength(src, 256);
  for j := 0 to 255 do src[j] := Byte(j);
  DeflateZlibStored(src, enc);
  good := InflateZlib(enc, outbuf, err);
  if not good then Fail('stored inflate: ' + err)
  else if not SameBytes(src, outbuf) then Fail('stored data mismatch')
  else writeln('OK stored roundtrip');
end;

procedure TestFixedHuffman;
{ zlib stream for 'hello world' produced by Python's zlib.compress(..., 9).
  Uses a fixed-Huffman deflate block (btype=1). }
begin
  SetLength(enc, 19);
  enc[0] := 120;  enc[1] := 218; enc[2] := 203; enc[3] := 72;
  enc[4] := 205;  enc[5] := 201; enc[6] := 201; enc[7] := 87;
  enc[8] := 40;   enc[9] := 207; enc[10] := 47; enc[11] := 202;
  enc[12] := 73;  enc[13] := 1;  enc[14] := 0;  enc[15] := 26;
  enc[16] := 11;  enc[17] := 4;  enc[18] := 93;
  good := InflateZlib(enc, outbuf, err);
  if not good then Fail('fixed huffman inflate: ' + err)
  else if Length(outbuf) <> 11 then Fail('fixed huffman length')
  else writeln('OK fixed huffman');
end;

procedure TestDynamicHuffman;
{ zlib stream for 'abcdefgh' repeated 1000 times, produced by Python's
  zlib.compress(..., 9).  Uses a dynamic-Huffman deflate block (btype=2). }
begin
  SetLength(enc, 42);
  enc[0] := 120;  enc[1] := 218; enc[2] := 237; enc[3] := 197;
  enc[4] := 49;   enc[5] := 1;   enc[6] := 0;   enc[7] := 32;
  enc[8] := 8;    enc[9] := 0;   enc[10] := 176; enc[11] := 172;
  enc[12] := 8;   enc[13] := 8;  enc[14] := 253; enc[15] := 19;
  enc[16] := 24;  enc[17] := 196; enc[18] := 237; enc[19] := 89;
  enc[20] := 156; enc[21] := 172; enc[22] := 190; enc[23] := 179;
  enc[24] := 97;  enc[25] := 219; enc[26] := 182; enc[27] := 109;
  enc[28] := 219; enc[29] := 182; enc[30] := 109; enc[31] := 219;
  enc[32] := 182; enc[33] := 109; enc[34] := 219; enc[35] := 246;
  enc[36] := 199; enc[37] := 63;  enc[38] := 29;  enc[39] := 207;
  enc[40] := 69;  enc[41] := 85;
  good := InflateZlib(enc, outbuf, err);
  if not good then Fail('dynamic huffman inflate: ' + err)
  else if Length(outbuf) <> 8000 then Fail('dynamic huffman length')
  else
  begin
    bad := 0;
    for i := 0 to 7999 do
      if outbuf[i] <> Byte(Ord('a') + (i mod 8)) then bad := 1;
    if bad <> 0 then Fail('dynamic huffman data')
    else writeln('OK dynamic huffman');
  end;
end;

procedure TestBadHeaderChecksum;
{ Valid zlib header is 0x78 0x01 for CM=8, no dict, level 0.  Flip a bit in
  the FLG byte so the CMF*256+FLG mod 31 check fails. }
begin
  SetLength(enc, 6);
  enc[0] := 120; enc[1] := 2; enc[2] := 1; enc[3] := 0;
  enc[4] := 255; enc[5] := 255;
  good := InflateZlib(enc, outbuf, err);
  if good or (err <> 'bad zlib header checksum') then
    Fail('bad header checksum: got [' + err + ']')
  else writeln('OK bad header checksum');
end;

procedure TestBadAdler;
{ Valid stored zlib stream for [0..7] but with the last trailer byte flipped. }
begin
  SetLength(enc, 19);
  enc[0] := 120;  enc[1] := 1;   enc[2] := 1;   enc[3] := 8;
  enc[4] := 0;    enc[5] := 247; enc[6] := 255; enc[7] := 0;
  enc[8] := 1;    enc[9] := 2;   enc[10] := 3;  enc[11] := 4;
  enc[12] := 5;   enc[13] := 6;  enc[14] := 7;  enc[15] := 0;
  enc[16] := 92;  enc[17] := 0;  enc[18] := 30;
  good := InflateZlib(enc, outbuf, err);
  if good or (err <> 'bad adler32') then
    Fail('bad adler32: got [' + err + ']')
  else writeln('OK bad adler32');
end;

procedure TestTruncated;
{ Stored block header promises 8 bytes but only 2 are present. }
begin
  SetLength(enc, 10);
  enc[0] := 120; enc[1] := 1; enc[2] := 1; enc[3] := 8;
  enc[4] := 0;   enc[5] := 247; enc[6] := 255; enc[7] := 0;
  enc[8] := 1;   enc[9] := 0;
  good := InflateZlib(enc, outbuf, err);
  if good then Fail('truncated accepted')
  else writeln('OK truncated stream');
end;

procedure TestReservedBlockType;
{ zlib header + bfinal=1, btype=3 (reserved). }
begin
  SetLength(enc, 8);
  enc[0] := 120; enc[1] := 1; enc[2] := 7; enc[3] := 0;
  enc[4] := 0;   enc[5] := 0;  enc[6] := 0; enc[7] := 0;
  good := InflateZlib(enc, outbuf, err);
  if good or (err <> 'reserved deflate block type') then
    Fail('reserved block type: got [' + err + ']')
  else writeln('OK reserved block type');
end;

function IsHelloWorld(const b: TByteArray): Boolean;
const s: AnsiString = 'hello world';
var j: Integer;
begin
  Result := False;
  if Length(b) <> Length(s) then Exit;
  for j := 0 to Length(s) - 1 do
    if b[j] <> Byte(s[j + 1]) then Exit;
  Result := True;
end;

procedure FillGzipHelloWorld;
{ gzip member for 'hello world' (Python gzip, mtime=0). }
begin
  SetLength(enc, 31);
  enc[0]:=31; enc[1]:=139; enc[2]:=8; enc[3]:=0; enc[4]:=0; enc[5]:=0;
  enc[6]:=0; enc[7]:=0; enc[8]:=2; enc[9]:=255; enc[10]:=203; enc[11]:=72;
  enc[12]:=205; enc[13]:=201; enc[14]:=201; enc[15]:=87; enc[16]:=40;
  enc[17]:=207; enc[18]:=47; enc[19]:=202; enc[20]:=73; enc[21]:=1; enc[22]:=0;
  enc[23]:=133; enc[24]:=17; enc[25]:=74; enc[26]:=13; enc[27]:=11; enc[28]:=0;
  enc[29]:=0; enc[30]:=0;
end;

procedure TestGzip;
begin
  FillGzipHelloWorld;
  good := InflateGzip(enc, outbuf, err);
  if not good then Fail('gzip inflate: ' + err)
  else if not IsHelloWorld(outbuf) then Fail('gzip data mismatch')
  else writeln('OK gzip');
end;

procedure TestGzipBadCrc;
{ same gzip member, CRC32 first trailer byte corrupted. }
begin
  FillGzipHelloWorld;
  enc[23] := 132;                 { flip the CRC32 LSB }
  good := InflateGzip(enc, outbuf, err);
  if good or (err <> 'bad gzip crc32') then
    Fail('gzip bad crc: got [' + err + ']')
  else writeln('OK gzip bad crc');
end;

procedure TestRawDeflate;
{ bare RFC1951 deflate of 'hello world' (no wrapper). }
begin
  SetLength(enc, 13);
  enc[0]:=203; enc[1]:=72; enc[2]:=205; enc[3]:=201; enc[4]:=201; enc[5]:=87;
  enc[6]:=40; enc[7]:=207; enc[8]:=47; enc[9]:=202; enc[10]:=73; enc[11]:=1;
  enc[12]:=0;
  good := InflateRawBytes(enc, outbuf, err);
  if not good then Fail('raw deflate inflate: ' + err)
  else if not IsHelloWorld(outbuf) then Fail('raw deflate data mismatch')
  else writeln('OK raw deflate');
end;

{ A RAW stored-block stream -- the cell this file's two raw/stored tests left
  uncovered, and the one a real bug lived in.

  TestStoredRoundtrip exercises stored blocks through the ZLIB wrapper, and
  TestRawDeflate exercises the RAW entry point with a FIXED-HUFFMAN stream (its
  first byte 203 = BTYPE 01). Full marginal coverage of both axes, and nothing at
  their intersection. InflateStored bounded stored data by `Length(gData) - 4`,
  assuming every stream ends in a 4-byte checksum -- correct for the wrapped case,
  so TestStoredRoundtrip passed, and never reached through the raw case, so
  TestRawDeflate passed. A valid raw stored stream was rejected as `truncated
  stored data` for as long as both tests were green.

  POSITIVE CONTROL: this case FAILS with `truncated stored data` against the
  pre-fix unit and passes after, verified both ways rather than asserted. If it
  ever cannot fail, it has stopped testing the bound.

  'hello world' as one final stored block: BFINAL|BTYPE byte, LEN, NLEN, data. }
procedure TestRawStored;
var j: Integer;
    lit: AnsiString;
begin
  lit := 'hello world';
  SetLength(enc, 5 + Length(lit));
  enc[0] := 1;                                   { BFINAL=1, BTYPE=00 stored }
  enc[1] := Byte(Length(lit) and $FF);           { LEN  lo }
  enc[2] := Byte((Length(lit) shr 8) and $FF);   { LEN  hi }
  enc[3] := Byte((65535 - Length(lit)) and $FF);         { NLEN lo }
  enc[4] := Byte(((65535 - Length(lit)) shr 8) and $FF); { NLEN hi }
  for j := 1 to Length(lit) do enc[4 + j] := Byte(lit[j]);
  good := InflateRawBytes(enc, outbuf, err);
  if not good then Fail('raw stored inflate: ' + err)
  else if not IsHelloWorld(outbuf) then Fail('raw stored data mismatch')
  else writeln('OK raw stored');
end;


{ ---- DeflateZlib (the compressing encoder) ----------------------------------

  These five rows exist because `compress` went from stored blocks to a real
  LZ77 + fixed-Huffman encoder on 2026-09-13, and a round trip alone would not
  have noticed if it had quietly gone back. THE ROUND TRIP IS THE WEAKEST OF
  THEM: DeflateZlibStored passed it for months while compressing nothing, so a
  size assertion is what actually tests the claim. }

var defSrc, defEnc, defEnc2, defStored: TByteArray;

procedure BuildRepeated(n, value: Integer);
var j: Integer;
begin
  SetLength(defSrc, n);
  for j := 0 to n - 1 do defSrc[j] := Byte(value);
end;

{ An LCG rather than a fixed blob: it is reproducible, it is the same sequence
  on every target, and it has no matches for LZ77 to find, which is the case the
  stored fallback exists for. }
procedure BuildPseudoRandom(n, seed: Integer);
var j, st: Integer;
begin
  SetLength(defSrc, n);
  st := seed;
  for j := 0 to n - 1 do
  begin
    st := (st * 1103515245 + 12345) and $3FFFFFFF;
    defSrc[j] := Byte((st shr 16) and $FF);
  end;
end;

procedure BuildLowEntropy(n, seed: Integer);
var j, st: Integer;
begin
  SetLength(defSrc, n);
  st := seed;
  for j := 0 to n - 1 do
  begin
    st := (st * 1103515245 + 12345) and $3FFFFFFF;
    defSrc[j] := Byte((st shr 16) and 15);
  end;
end;

function DeflateRoundTrips(level: Integer): Boolean;
begin
  Result := False;
  DeflateZlib(defSrc, defEnc, level);
  if not InflateZlib(defEnc, outbuf, err) then Exit;
  Result := SameBytes(defSrc, outbuf);
end;

procedure TestDeflateRoundtrip;
var j, n: Integer;
begin
  { Shapes chosen for their edges, not for variety: 0 and 1 and 2 bytes are all
    shorter than the 3-byte minimum match, 258 and 259 sit either side of the
    maximum match length, and 70000 crosses the 65535 stored-block boundary that
    the fallback path still has to get right. }
  SetLength(defSrc, 0);
  if not DeflateRoundTrips(6) then begin Fail('deflate roundtrip: empty'); Exit; end;
  for n := 1 to 3 do
  begin
    BuildRepeated(n, 65);
    if not DeflateRoundTrips(6) then begin Fail('deflate roundtrip: short'); Exit; end;
  end;
  for n := 257 to 260 do
  begin
    BuildRepeated(n, 7);
    if not DeflateRoundTrips(6) then begin Fail('deflate roundtrip: max-match'); Exit; end;
  end;
  BuildPseudoRandom(4096, 12345);
  if not DeflateRoundTrips(6) then begin Fail('deflate roundtrip: random'); Exit; end;
  BuildLowEntropy(30000, 999);
  if not DeflateRoundTrips(6) then begin Fail('deflate roundtrip: low entropy'); Exit; end;
  SetLength(defSrc, 70000);
  for j := 0 to 69999 do defSrc[j] := Byte(j mod 3);
  if not DeflateRoundTrips(6) then begin Fail('deflate roundtrip: 70000'); Exit; end;
  { Every level, on input with matches in it, so a broken level config cannot
    hide behind level 6 being the only one anybody runs. }
  BuildLowEntropy(8000, 4242);
  for j := 0 to 9 do
    if not DeflateRoundTrips(j) then
    begin
      Fail('deflate roundtrip: level'); Exit;
    end;
  writeln('OK deflate roundtrip');
end;

{ THE ROW THAT WOULD HAVE CAUGHT THE OLD BEHAVIOUR. 2000 identical bytes went
  out as 2011 under the stored encoder; CPython gives 23. A bound of 64 is loose
  enough to survive an encoder change and tight enough that stored blocks can
  never pass it. }
procedure TestDeflateCompresses;
begin
  BuildRepeated(2000, 65);
  DeflateZlib(defSrc, defEnc, 6);
  if Length(defEnc) > 64 then
    Fail('deflate did not compress: 2000 identical bytes -> ' + IStr(Length(defEnc)))
  else if not InflateZlib(defEnc, outbuf, err) then
    Fail('deflate compressed but did not inflate: ' + err)
  else if not SameBytes(defSrc, outbuf) then
    Fail('deflate compressed to the wrong bytes')
  else
    writeln('OK deflate compresses');
end;

{ A fixed-Huffman block spends 8 or 9 bits on every literal, so input with no
  matches EXPANDS -- measured at 4331 bytes out of 4096 in before the stored
  fallback went in. This row is the fallback's positive control: it fails if the
  fallback is removed, which a round-trip row would not notice. }
procedure TestDeflateNoExpansion;
var bound: Integer;
begin
  BuildPseudoRandom(4096, 12345);
  DeflateZlib(defSrc, defEnc, 6);
  bound := 2 + 5 + Length(defSrc) + 4;   { one stored block + zlib wrapper }
  if Length(defEnc) > bound then
    Fail('deflate expanded incompressible input: ' + IStr(Length(defEnc))
         + ' > ' + IStr(bound))
  else if not InflateZlib(defEnc, outbuf, err) then
    Fail('deflate fallback did not inflate: ' + err)
  else if not SameBytes(defSrc, outbuf) then
    Fail('deflate fallback produced the wrong bytes')
  else
    writeln('OK deflate no expansion');
end;

{ Level 0 means STORED to CPython, and routing it anywhere else would be a
  divergence a caller can see in the output size. Compared against
  DeflateZlibStored's own bytes rather than against a length, so it cannot pass
  by coincidence. }
procedure TestDeflateLevelZero;
begin
  BuildRepeated(2000, 65);
  DeflateZlib(defSrc, defEnc, 0);
  DeflateZlibStored(defSrc, defStored);
  if not SameBytes(defEnc, defStored) then
    Fail('level 0 is not the stored encoder')
  else
    writeln('OK deflate level 0 is stored');
end;

{ THE ROW THAT CAUGHT THE ONLY REAL BUG IN THIS ENCODER, and it caught it after
  the rest of the suite was green.

  Literals 144..255 carry NINE-bit codes in the fixed alphabet; 0..143 carry
  eight. When the emitter moved to deriving the fixed codes canonically from a
  length table instead of writing the RFC's constants, the table stopped at
  symbol 285 and left out 286/287 -- present-but-unused eight-bit codes. Canonical
  assignment is a running count over all lengths, so blCount[8] fell from 152 to
  150 and EVERY nine-bit code was wrong. Streams decoded as `bad adler32`, `bad
  length code`, or plausible garbage.

  NOTHING ELSE HERE COULD SEE IT. The short round-trip cases used repeated 'A'
  (65), the long ones used byte values below 144 or fell into the stored
  fallback, and the one random case was 4096 bytes -- incompressible, so stored
  won and no Huffman code was emitted at all. A whole half of the literal
  alphabet was untested while every row read green.

  So: pseudo-random bytes across the full 0..255 range, at every length from 0 to
  200, which is short enough that a Huffman block always beats stored and long
  enough to cross the 3-byte minimum match. The lengths are walked rather than
  sampled because the first failures were at n=1, 3, 4, 5 -- sizes an
  interesting-values list would have called degenerate and skipped. }
procedure TestDeflateHighLiterals;
var n, i, seed, failures: Integer;
begin
  failures := 0;
  seed := 1;
  for n := 0 to 200 do
  begin
    SetLength(defSrc, n);
    for i := 0 to n - 1 do
    begin
      seed := (seed * 1103515245 + 12345) and $3FFFFFFF;
      defSrc[i] := Byte((seed shr 16) and $FF);
    end;
    DeflateZlib(defSrc, defEnc, 6);
    if not InflateZlib(defEnc, outbuf, err) then
      failures := failures + 1
    else if not SameBytes(defSrc, outbuf) then
      failures := failures + 1;
  end;
  if failures > 0 then
    Fail('deflate high literals: ' + IStr(failures) + ' of 201 lengths failed')
  else
    writeln('OK deflate high literals');
end;

{ THE ROW THAT PROVES BOTH BLOCK TYPES ARE LIVE, and without it the dynamic
  encoder could be broken in a way nothing else here would notice. The driver
  emits stored, fixed and dynamic and keeps the smallest; if EmitDynamicHeader
  produced garbage-but-large output, fixed would simply always win, every other
  row would still pass, and the fitted tables would be dead code that looked
  exercised. Compare that to the shape CLAUDE.md warns about -- one passing part
  of a run supplying what a failing part needs.

  BTYPE lives in bits 1-2 of the first byte after the two-byte zlib header:
  0 = stored, 1 = fixed, 2 = dynamic. Both expectations are asymmetric on
  purpose -- a tiny input CANNOT pay for a fitted table, and a long skewed one
  cannot fail to, so neither row can be satisfied by the other's answer. }
function BlockTypeOf(const enc: TByteArray): Integer;
begin
  Result := -1;
  if Length(enc) < 3 then Exit;
  Result := (enc[2] shr 1) and 3;
end;

procedure TestDeflateBlockTypes;
var bt: Integer;
begin
  { 30000 bytes over 16 values: far too skewed for the fixed table's flat 8 bits
    per literal, so the fitted one must win. }
  BuildLowEntropy(30000, 999);
  DeflateZlib(defSrc, defEnc, 6);
  bt := BlockTypeOf(defEnc);
  if bt <> 2 then
  begin
    Fail('expected a dynamic block on skewed input, got btype ' + IStr(bt));
    Exit;
  end;
  { Two bytes cannot repay a code-length table, so fixed must win here. }
  SetLength(defSrc, 2);
  defSrc[0] := 1; defSrc[1] := 2;
  DeflateZlib(defSrc, defEnc, 6);
  bt := BlockTypeOf(defEnc);
  if bt <> 1 then
    Fail('expected a fixed block on two bytes, got btype ' + IStr(bt))
  else
    writeln('OK deflate picks block types');
end;

{ `level` SELECTS WORK. Without this row the level parameter could be accepted
  and dropped -- which is what it was before 2026-09-13 -- and every other row
  here would still pass. Low-entropy input is used because it has many short
  matches at scattered distances, which is the only shape where the chain bound
  and lazy matching actually bite; on highly repetitive input every level finds
  the same matches and ties legitimately.

  ASSERTS THAT THE LEVELS DIFFER, NOT THAT THEY ARE ORDERED, and the difference
  matters. The first version of this row required level 6 to beat level 1, which
  passed under fixed Huffman and is NOT a property deflate guarantees: once the
  encoder fits a code table to the symbols, a better match set can produce a
  worse distribution and a slightly larger block. Measured 2026-09-13 on this
  very input -- levels 1,2,3 give 17720, 17778, 17792, so level 2 is worse than
  level 1 while both are legal and both round-trip. An ordering assertion would
  have been a claim about optimality; what the parameter actually promises is
  that it changes the search, and that is what is checked here. }
procedure TestDeflateLevelsDiffer;
var lv, distinct, j: Integer;
    sizes: array[1..9] of Integer;
begin
  BuildLowEntropy(30000, 999);
  for lv := 1 to 9 do
  begin
    DeflateZlib(defSrc, defEnc, lv);
    sizes[lv] := Length(defEnc);
  end;
  distinct := 0;
  for lv := 1 to 9 do
  begin
    j := 1;
    while (j < lv) and (sizes[j] <> sizes[lv]) do j := j + 1;
    if j = lv then distinct := distinct + 1;
  end;
  if distinct < 2 then
    Fail('every level produced the same size (' + IStr(sizes[1])
         + ') -- level is not selecting anything')
  else
    writeln('OK deflate levels differ');
end;

begin
  bad := 0;
  TestStoredRoundtrip;
  TestFixedHuffman;
  TestDynamicHuffman;
  TestBadHeaderChecksum;
  TestBadAdler;
  TestTruncated;
  TestReservedBlockType;
  TestGzip;
  TestGzipBadCrc;
  TestRawDeflate;
  TestRawStored;
  TestDeflateRoundtrip;
  TestDeflateCompresses;
  TestDeflateNoExpansion;
  TestDeflateLevelZero;
  TestDeflateLevelsDiffer;
  TestDeflateBlockTypes;
  TestDeflateHighLiterals;
end.
