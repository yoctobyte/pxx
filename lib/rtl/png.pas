unit png;
{ PNG encoder/decoder.

  Supports non-interlaced 8-bit RGBA PNGs (color type 6). Encoding writes zlib
  streams made of uncompressed deflate blocks, so the output is valid PNG
  without depending on a compression library. Decoding accepts any valid deflate
  stream (stored, fixed Huffman, or dynamic Huffman) and implements all standard
  PNG scanline filters for RGBA. }

interface

uses image, hashing, zlib;

procedure PngEncodeRGBA(var img: TImage; var outBytes: TByteArray);
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

var
  LastError: AnsiString;
  gOut:  TByteArray;   { module-global encode buffer }
  gIdat: TByteArray;   { module-global IDAT accumulator during decode }

procedure SetErr(const s: AnsiString);
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

{ ---- byte-array builder helpers ---- }

procedure AbAppend(b: Byte);
var n: Integer;
begin
  n := Length(gOut);
  SetLength(gOut, n + 1);
  gOut[n] := b;
end;

procedure AbAppendArr(const b: TByteArray);
var i, n, m: Integer;
begin
  n := Length(gOut);
  m := Length(b);
  SetLength(gOut, n + m);
  for i := 0 to m - 1 do
    gOut[n + i] := b[i];
end;

procedure AbAppendU16LE(v: Integer);
begin
  AbAppend(Byte(v and $FF));
  AbAppend(Byte((v shr 8) and $FF));
end;

procedure AbAppendU32BE(v: LongWord);
begin
  AbAppend(Byte((v shr 24) and $FF));
  AbAppend(Byte((v shr 16) and $FF));
  AbAppend(Byte((v shr 8) and $FF));
  AbAppend(Byte(v and $FF));
end;

function AbReadU32BE(const data: TByteArray; pos: Integer): LongWord;
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

procedure AppendChunk(kind: LongWord; const payload: TByteArray);
var crc: LongWord;
begin
  AbAppendU32BE(LongWord(Length(payload)));
  AbAppend(Byte((kind shr 24) and $FF));
  AbAppend(Byte((kind shr 16) and $FF));
  AbAppend(Byte((kind shr 8) and $FF));
  AbAppend(Byte(kind and $FF));
  AbAppendArr(payload);
  crc := CRC32Chunk(kind, payload);
  AbAppendU32BE(crc);
end;

procedure BuildRawRGBA(var img: TImage; var raw: TByteArray);
var x, y, p: Integer; c: TRGBA;
begin
  SetLength(raw, img.Height * (1 + img.Width * 4));
  p := 0;
  for y := 0 to img.Height - 1 do
  begin
    raw[p] := 0;  { filter type: None }
    p := p + 1;
    for x := 0 to img.Width - 1 do
    begin
      c := ImageGetPixel(img, x, y);
      raw[p] := c.R; p := p + 1;
      raw[p] := c.G; p := p + 1;
      raw[p] := c.B; p := p + 1;
      raw[p] := c.A; p := p + 1;
    end;
  end;
end;

{ ---- encoder ---- }

procedure PngEncodeRGBA(var img: TImage; var outBytes: TByteArray);
var ihdr, raw, z, empty: TByteArray;
    i, n: Integer;
begin
  SetLength(gOut, 0);
  AbAppend(PNG_SIG0); AbAppend(PNG_SIG1);
  AbAppend(PNG_SIG2); AbAppend(PNG_SIG3);
  AbAppend(PNG_SIG4); AbAppend(PNG_SIG5);
  AbAppend(PNG_SIG6); AbAppend(PNG_SIG7);

  SetLength(ihdr, 13);
  ihdr[0] := Byte((img.Width shr 24) and $FF);
  ihdr[1] := Byte((img.Width shr 16) and $FF);
  ihdr[2] := Byte((img.Width shr 8) and $FF);
  ihdr[3] := Byte(img.Width and $FF);
  ihdr[4] := Byte((img.Height shr 24) and $FF);
  ihdr[5] := Byte((img.Height shr 16) and $FF);
  ihdr[6] := Byte((img.Height shr 8) and $FF);
  ihdr[7] := Byte(img.Height and $FF);
  ihdr[8] := 8;  { bit depth }
  ihdr[9] := 6;  { RGBA }
  ihdr[10] := 0; { compression }
  ihdr[11] := 0; { filter }
  ihdr[12] := 0; { no interlace }
  AppendChunk(ChunkName('I', 'H', 'D', 'R'), ihdr);

  BuildRawRGBA(img, raw);
  DeflateZlibStored(raw, z);
  AppendChunk(ChunkName('I', 'D', 'A', 'T'), z);

  SetLength(empty, 0);
  AppendChunk(ChunkName('I', 'E', 'N', 'D'), empty);

  n := Length(gOut);
  SetLength(outBytes, n);
  for i := 0 to n - 1 do
    outBytes[i] := gOut[i];
  SetLength(gOut, 0);
end;

{ ---- filters ---- }

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

function UnfilterRGBA(const raw: TByteArray; width, height: Integer;
                       var pixels: TByteArray): Boolean;
var rowBytes, x, y, p, dst, filter, val, left, up, upLeft: Integer;
begin
  Result := False;
  rowBytes := width * 4;
  if Length(raw) <> height * (rowBytes + 1) then
  begin
    SetErr('bad raw image length');
    Exit;
  end;
  SetLength(pixels, width * height * 4);
  p   := 0;
  dst := 0;
  for y := 0 to height - 1 do
  begin
    filter := raw[p];
    p := p + 1;
    if filter > 4 then begin SetErr('bad filter'); Exit; end;
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

{ ---- decoder ---- }

procedure IdatAppend(const b: TByteArray);
var i, n, m: Integer;
begin
  n := Length(gIdat);
  m := Length(b);
  SetLength(gIdat, n + m);
  for i := 0 to m - 1 do
    gIdat[n + i] := b[i];
end;

function PngDecodeRGBA(const data: TByteArray; var img: TImage): Boolean;
var pos, chunkLen, endPos, width, height: Integer;
    kind, gotCrc, wantCrc: LongWord;
    payload, raw, px: TByteArray;
    seenIHDR, seenIEND: Boolean;
    i: Integer; c: TRGBA;
    zlibErr: AnsiString;
begin
  Result := False;
  SetErr('');
  ImageFree(img);
  if not PngSignatureValid(data) then begin SetErr('bad png signature'); Exit; end;
  pos := 8;
  width := 0; height := 0;
  SetLength(gIdat, 0);
  seenIHDR := False; seenIEND := False;
  while pos < Length(data) do
  begin
    if pos + 8 > Length(data) then begin SetErr('truncated chunk header'); Exit; end;
    chunkLen := Integer(AbReadU32BE(data, pos));
    kind     := AbReadU32BE(data, pos + 4);
    pos := pos + 8;
    if (chunkLen < 0) or (pos + chunkLen + 4 > Length(data)) then
    begin
      SetErr('truncated chunk data');
      Exit;
    end;
    SetLength(payload, chunkLen);
    for i := 0 to chunkLen - 1 do payload[i] := data[pos + i];
    gotCrc  := AbReadU32BE(data, pos + chunkLen);
    wantCrc := CRC32Chunk(kind, payload);
    if gotCrc <> wantCrc then begin SetErr('bad chunk crc'); Exit; end;
    pos := pos + chunkLen + 4;

    if kind = ChunkName('I', 'H', 'D', 'R') then
    begin
      if seenIHDR then begin SetErr('duplicate ihdr'); Exit; end;
      if chunkLen <> 13 then begin SetErr('bad ihdr length'); Exit; end;
      width  := Integer(AbReadU32BE(payload, 0));
      height := Integer(AbReadU32BE(payload, 4));
      if (width <= 0) or (height <= 0) then begin SetErr('bad dimensions'); Exit; end;
      if (payload[8] <> 8) or (payload[9] <> 6) or (payload[10] <> 0) or
         (payload[11] <> 0) or (payload[12] <> 0) then
      begin
        SetErr('unsupported ihdr');
        Exit;
      end;
      seenIHDR := True;
    end
    else if kind = ChunkName('I', 'D', 'A', 'T') then
    begin
      if not seenIHDR then begin SetErr('idat before ihdr'); Exit; end;
      IdatAppend(payload);
    end
    else if kind = ChunkName('I', 'E', 'N', 'D') then
    begin
      seenIEND := True;
      Break;
    end;
  end;

  if not seenIHDR then begin SetErr('missing ihdr'); Exit; end;
  if not seenIEND then begin SetErr('missing iend'); Exit; end;
  if Length(gIdat) = 0 then begin SetErr('missing idat'); Exit; end;

  if not InflateZlib(gIdat, raw, zlibErr) then
  begin
    SetErr(zlibErr);
    Exit;
  end;

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
