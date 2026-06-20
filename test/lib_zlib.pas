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

begin
  bad := 0;
  TestStoredRoundtrip;
  TestFixedHuffman;
  TestDynamicHuffman;
  TestBadHeaderChecksum;
  TestBadAdler;
  TestTruncated;
  TestReservedBlockType;
end.
