unit png;
{ PNG encoder/decoder first slice.

  Supports non-interlaced 8-bit RGBA PNGs (color type 6). Encoding writes zlib
  streams made of uncompressed deflate blocks, so the output is valid PNG
  without depending on a compression library. Decoding accepts the same stored
  deflate streams and implements all standard PNG scanline filters for RGBA. }

interface

uses image;

type
  TByteArray = array of Byte;

function PngEncodeRGBA(const img: TImage): TByteArray;
function PngDecodeRGBA(const data: TByteArray; var img: TImage): Boolean;
function PngLastError: AnsiString;
function PngSignatureValid(const data: TByteArray): Boolean;

implementation

const
  PNG_SIG0 = 137;
  PNG_SIG1 = 80;
  PNG_SIG2 = 78;
  PNG_SIG3 = 71;
  PNG_SIG4 = 13;
  PNG_SIG5 = 10;
  PNG_SIG6 = 26;
  PNG_SIG7 = 10;
  ADLER_MOD = 65521;

var
  LastError: AnsiString;

procedure SetError(const s: AnsiString);
begin
  LastError := s;
end;

function PngLastError: AnsiString;
begin
  Result := LastError;
end;

function PngSignatureValid(const data: TByteArray): Boolean;
begin
  Result := (Length(data) >= 8) and
            (data[0] = PNG_SIG0) and (data[1] = PNG_SIG1) and
            (data[2] = PNG_SIG2) and (data[3] = PNG_SIG3) and
            (data[4] = PNG_SIG4) and (data[5] = PNG_SIG5) and
            (data[6] = PNG_SIG6) and (data[7] = PNG_SIG7);
end;

procedure AppendByte(var a: TByteArray; b: Byte);
var n: Integer;
begin
  n := Length(a);
  SetLength(a, n + 1);
  a[n] := b;
end;

procedure AppendBytes(var a: TByteArray; const b: TByteArray);
var i, n, m: Integer;
begin
  n := Length(a);
  m := Length(b);
  SetLength(a, n + m);
  for i := 0 to m - 1 do
    a[n + i] := b[i];
end;

procedure AppendU16LE(var a: TByteArray; v: Integer);
begin
  AppendByte(a, Byte(v and $FF));
  AppendByte(a, Byte((v shr 8) and $FF));
end;

procedure AppendU32BE(var a: TByteArray; v: LongWord);
begin
  AppendByte(a, Byte((v shr 24) and $FF));
  AppendByte(a, Byte((v shr 16) and $FF));
  AppendByte(a, Byte((v shr 8) and $FF));
  AppendByte(a, Byte(v and $FF));
end;

function ReadU32BE(const data: TByteArray; pos: Integer): LongWord;
begin
  Result := (LongWord(data[pos]) shl 24) or
            (LongWord(data[pos + 1]) shl 16) or
            (LongWord(data[pos + 2]) shl 8) or
            LongWord(data[pos + 3]);
end;

function ChunkName(a, b, c, d: Char): LongWord;
begin
  Result := (LongWord(Ord(a)) shl 24) or
            (LongWord(Ord(b)) shl 16) or
            (LongWord(Ord(c)) shl 8) or
            LongWord(Ord(d));
end;

function CRC32Update(crc: LongWord; b: Byte): LongWord;
var i: Integer;
begin
  crc := crc xor LongWord(b);
  for i := 0 to 7 do
  begin
    if (crc and 1) <> 0 then
      crc := (crc shr 1) xor LongWord($EDB88320)
    else
      crc := crc shr 1;
  end;
  Result := crc;
end;

function CRC32Chunk(kind: LongWord; const payload: TByteArray): LongWord;
var crc: LongWord; i: Integer;
begin
  crc := LongWord($FFFFFFFF);
  crc := CRC32Update(crc, Byte((kind shr 24) and $FF));
  crc := CRC32Update(crc, Byte((kind shr 16) and $FF));
  crc := CRC32Update(crc, Byte((kind shr 8) and $FF));
  crc := CRC32Update(crc, Byte(kind and $FF));
  for i := 0 to Length(payload) - 1 do
    crc := CRC32Update(crc, payload[i]);
  Result := crc xor LongWord($FFFFFFFF);
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

procedure AppendChunk(var outp: TByteArray; kind: LongWord; const payload: TByteArray);
var crc: LongWord;
begin
  AppendU32BE(outp, LongWord(Length(payload)));
  AppendByte(outp, Byte((kind shr 24) and $FF));
  AppendByte(outp, Byte((kind shr 16) and $FF));
  AppendByte(outp, Byte((kind shr 8) and $FF));
  AppendByte(outp, Byte(kind and $FF));
  AppendBytes(outp, payload);
  crc := CRC32Chunk(kind, payload);
  AppendU32BE(outp, crc);
end;

function BuildRawRGBA(const img: TImage): TByteArray;
var x, y, p: Integer; c: TRGBA;
begin
  SetLength(Result, img.Height * (1 + img.Width * 4));
  p := 0;
  for y := 0 to img.Height - 1 do
  begin
    Result[p] := 0;  { filter type: None }
    p := p + 1;
    for x := 0 to img.Width - 1 do
    begin
      c := ImageGetPixel(img, x, y);
      Result[p] := c.R; p := p + 1;
      Result[p] := c.G; p := p + 1;
      Result[p] := c.B; p := p + 1;
      Result[p] := c.A; p := p + 1;
    end;
  end;
end;

function ZlibStore(const raw: TByteArray): TByteArray;
var pos, remain, blockLen: Integer; final: Byte; ad: LongWord;
begin
  SetLength(Result, 0);
  AppendByte(Result, $78);
  AppendByte(Result, $01);
  pos := 0;
  repeat
    remain := Length(raw) - pos;
    if remain > 65535 then
      blockLen := 65535
    else
      blockLen := remain;
    if pos + blockLen >= Length(raw) then
      final := 1
    else
      final := 0;
    AppendByte(Result, final);
    AppendU16LE(Result, blockLen);
    AppendU16LE(Result, 65535 - blockLen);
    for remain := 0 to blockLen - 1 do
      AppendByte(Result, raw[pos + remain]);
    pos := pos + blockLen;
  until pos >= Length(raw);
  ad := Adler32(raw);
  AppendU32BE(Result, ad);
end;

function PngEncodeRGBA(const img: TImage): TByteArray;
var ihdr, raw, z: TByteArray;
begin
  SetLength(Result, 0);
  AppendByte(Result, PNG_SIG0); AppendByte(Result, PNG_SIG1);
  AppendByte(Result, PNG_SIG2); AppendByte(Result, PNG_SIG3);
  AppendByte(Result, PNG_SIG4); AppendByte(Result, PNG_SIG5);
  AppendByte(Result, PNG_SIG6); AppendByte(Result, PNG_SIG7);

  SetLength(ihdr, 0);
  AppendU32BE(ihdr, LongWord(img.Width));
  AppendU32BE(ihdr, LongWord(img.Height));
  AppendByte(ihdr, 8);  { bit depth }
  AppendByte(ihdr, 6);  { RGBA }
  AppendByte(ihdr, 0);  { compression }
  AppendByte(ihdr, 0);  { filter }
  AppendByte(ihdr, 0);  { no interlace }
  AppendChunk(Result, ChunkName('I', 'H', 'D', 'R'), ihdr);

  raw := BuildRawRGBA(img);
  z := ZlibStore(raw);
  AppendChunk(Result, ChunkName('I', 'D', 'A', 'T'), z);

  SetLength(raw, 0);
  AppendChunk(Result, ChunkName('I', 'E', 'N', 'D'), raw);
end;

function ReadBits(const data: TByteArray; var bitpos: Integer; nbits: Integer; var ok: Boolean): Integer;
var i, bytePos, bit: Integer;
begin
  Result := 0;
  for i := 0 to nbits - 1 do
  begin
    bytePos := bitpos div 8;
    if bytePos >= Length(data) then
    begin
      ok := False;
      Exit;
    end;
    bit := (data[bytePos] shr (bitpos mod 8)) and 1;
    Result := Result or (bit shl i);
    bitpos := bitpos + 1;
  end;
end;

function InflateStoredZlib(const z: TByteArray; var raw: TByteArray): Boolean;
var bitpos, bfinal, btype, bytePos, len, nlen, i: Integer;
    ok: Boolean; wantAdler, gotAdler: LongWord;
begin
  Result := False;
  SetLength(raw, 0);
  if Length(z) < 6 then begin SetError('zlib stream too short'); Exit; end;
  if ((Integer(z[0]) * 256 + Integer(z[1])) mod 31) <> 0 then
  begin
    SetError('bad zlib header');
    Exit;
  end;
  bitpos := 16;
  repeat
    ok := True;
    bfinal := ReadBits(z, bitpos, 1, ok);
    btype := ReadBits(z, bitpos, 2, ok);
    if not ok then begin SetError('truncated deflate header'); Exit; end;
    if btype <> 0 then begin SetError('compressed deflate block unsupported'); Exit; end;
    if (bitpos mod 8) <> 0 then bitpos := ((bitpos div 8) + 1) * 8;
    bytePos := bitpos div 8;
    if bytePos + 4 > Length(z) - 4 then begin SetError('truncated stored block'); Exit; end;
    len := Integer(z[bytePos]) or (Integer(z[bytePos + 1]) shl 8);
    nlen := Integer(z[bytePos + 2]) or (Integer(z[bytePos + 3]) shl 8);
    if nlen <> 65535 - len then begin SetError('bad stored block length'); Exit; end;
    bytePos := bytePos + 4;
    if bytePos + len > Length(z) - 4 then begin SetError('truncated stored data'); Exit; end;
    for i := 0 to len - 1 do
      AppendByte(raw, z[bytePos + i]);
    bitpos := (bytePos + len) * 8;
  until bfinal <> 0;
  bytePos := bitpos div 8;
  if bytePos + 4 <> Length(z) then begin SetError('trailing zlib data'); Exit; end;
  wantAdler := ReadU32BE(z, bytePos);
  gotAdler := Adler32(raw);
  if wantAdler <> gotAdler then begin SetError('bad adler32'); Exit; end;
  Result := True;
end;

function Paeth(a, b, c: Integer): Integer;
var p, pa, pb, pc: Integer;
begin
  p := a + b - c;
  pa := p - a; if pa < 0 then pa := -pa;
  pb := p - b; if pb < 0 then pb := -pb;
  pc := p - c; if pc < 0 then pc := -pc;
  if (pa <= pb) and (pa <= pc) then Result := a
  else if pb <= pc then Result := b
  else Result := c;
end;

function UnfilterRGBA(const raw: TByteArray; width, height: Integer; var pixels: TByteArray): Boolean;
var rowBytes, x, y, p, dst, filter, val, left, up, upLeft: Integer;
begin
  Result := False;
  rowBytes := width * 4;
  if Length(raw) <> height * (rowBytes + 1) then
  begin
    SetError('bad raw image length');
    Exit;
  end;
  SetLength(pixels, width * height * 4);
  p := 0;
  dst := 0;
  for y := 0 to height - 1 do
  begin
    filter := raw[p];
    p := p + 1;
    if filter > 4 then begin SetError('bad filter'); Exit; end;
    for x := 0 to rowBytes - 1 do
    begin
      val := raw[p]; p := p + 1;
      if x >= 4 then left := pixels[dst - 4] else left := 0;
      if y > 0 then up := pixels[dst - rowBytes] else up := 0;
      if (x >= 4) and (y > 0) then upLeft := pixels[dst - rowBytes - 4] else upLeft := 0;
      if filter = 1 then val := (val + left) and $FF
      else if filter = 2 then val := (val + up) and $FF
      else if filter = 3 then val := (val + ((left + up) div 2)) and $FF
      else if filter = 4 then val := (val + Paeth(left, up, upLeft)) and $FF;
      pixels[dst] := Byte(val);
      dst := dst + 1;
    end;
  end;
  Result := True;
end;

function PngDecodeRGBA(const data: TByteArray; var img: TImage): Boolean;
var pos, chunkLen, endPos, width, height: Integer; kind, gotCrc, wantCrc: LongWord;
    payload, idat, raw, px: TByteArray; seenIHDR, seenIEND: Boolean; i: Integer;
    c: TRGBA;
begin
  Result := False;
  SetError('');
  ImageFree(img);
  if not PngSignatureValid(data) then begin SetError('bad png signature'); Exit; end;
  pos := 8;
  width := 0; height := 0;
  SetLength(idat, 0);
  seenIHDR := False; seenIEND := False;
  while pos < Length(data) do
  begin
    if pos + 8 > Length(data) then begin SetError('truncated chunk header'); Exit; end;
    chunkLen := Integer(ReadU32BE(data, pos));
    kind := ReadU32BE(data, pos + 4);
    pos := pos + 8;
    if (chunkLen < 0) or (pos + chunkLen + 4 > Length(data)) then
    begin
      SetError('truncated chunk data');
      Exit;
    end;
    SetLength(payload, chunkLen);
    for i := 0 to chunkLen - 1 do payload[i] := data[pos + i];
    gotCrc := ReadU32BE(data, pos + chunkLen);
    wantCrc := CRC32Chunk(kind, payload);
    if gotCrc <> wantCrc then begin SetError('bad chunk crc'); Exit; end;
    pos := pos + chunkLen + 4;

    if kind = ChunkName('I', 'H', 'D', 'R') then
    begin
      if seenIHDR then begin SetError('duplicate ihdr'); Exit; end;
      if chunkLen <> 13 then begin SetError('bad ihdr length'); Exit; end;
      width := Integer(ReadU32BE(payload, 0));
      height := Integer(ReadU32BE(payload, 4));
      if (width <= 0) or (height <= 0) then begin SetError('bad dimensions'); Exit; end;
      if (payload[8] <> 8) or (payload[9] <> 6) or (payload[10] <> 0) or
         (payload[11] <> 0) or (payload[12] <> 0) then
      begin
        SetError('unsupported ihdr');
        Exit;
      end;
      seenIHDR := True;
    end
    else if kind = ChunkName('I', 'D', 'A', 'T') then
    begin
      if not seenIHDR then begin SetError('idat before ihdr'); Exit; end;
      AppendBytes(idat, payload);
    end
    else if kind = ChunkName('I', 'E', 'N', 'D') then
    begin
      seenIEND := True;
      Break;
    end;
  end;

  if not seenIHDR then begin SetError('missing ihdr'); Exit; end;
  if not seenIEND then begin SetError('missing iend'); Exit; end;
  if Length(idat) = 0 then begin SetError('missing idat'); Exit; end;
  if not InflateStoredZlib(idat, raw) then Exit;
  if not UnfilterRGBA(raw, width, height, px) then Exit;

  ImageInit(img, width, height);
  endPos := 0;
  for i := 0 to ImagePixelCount(img) - 1 do
  begin
    c.R := px[endPos]; endPos := endPos + 1;
    c.G := px[endPos]; endPos := endPos + 1;
    c.B := px[endPos]; endPos := endPos + 1;
    c.A := px[endPos]; endPos := endPos + 1;
    img.Pixels[i] := c;
  end;
  Result := True;
end;

end.
