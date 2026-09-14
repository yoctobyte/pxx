{ SPDX-License-Identifier: Zlib }
unit png;
{$MODE PXX}   { our dialect; the FPC-parity strict-* flags do not judge this file }
{ PNG encoder/decoder.

  DECODES every non-interlaced colour type at every bit depth the spec allows:
  grayscale (0) at 1/2/4/8/16, truecolour (2) at 8/16, palette (3) at 1/2/4/8
  with PLTE and optional tRNS, grayscale+alpha (4) at 8/16 and RGBA (6) at 8/16.
  Everything is widened to 8-bit RGBA on the way out, so TImage stays one shape.
  Any valid deflate stream (stored, fixed or dynamic Huffman) and all five
  standard scanline filters.

  INTERLACED (Adam7) IS REFUSED, LOUDLY AND BY NAME. It is the one thing in the
  base spec this decoder does not do, and a silent wrong image is the failure
  worth avoiding -- the filter arithmetic is per-pass over seven sub-images, so
  reading an interlaced file as if it were progressive produces a plausible
  scrambled picture rather than an error.

  ENCODES 8-bit RGBA only (colour type 6), which is deliberate: an encoder has
  no compatibility obligation the way a decoder does, and one output shape that
  every reader accepts is worth more than palette optimisation.

  THIS COMMENT SAID "8-bit RGBA only" AND "uncompressed deflate blocks" UNTIL
  2026-09-14, and both halves had gone stale in opposite directions -- the
  encoder had moved to the real deflate encoder on 09-13 and the decoder had
  never handled anything but type 6. The first was a comment lagging the code;
  the second was the code lagging what a caller needs, and PIL opening a real
  palette PNG is what found it. }

interface

uses image, hashing, zlib;

procedure PngEncodeRGBA(var img: TImage; var outBytes: TByteArray);
function PngDecodeRGBA(const data: TByteArray; var img: TImage): Boolean;
function PngLastError: AnsiString;
function PngSignatureValid(const data: TByteArray): Boolean;

{ WHAT THE LAST DECODE READ OUT OF IHDR. Added for pil.pas, which has to report
  a truthful `im.mode`: every image is RGBA once it leaves here, so a caller
  asking the IMAGE what it is would always hear "RGBA" and a program branching
  on mode would act on a widening we performed rather than on the file.

  MODULE-GLOBAL "last" STATE, matching PngLastError, which is the existing idiom
  in this unit -- and carrying the same caveat: it describes the most recent
  PngDecodeRGBA call on this thread and nothing else. Read it immediately after
  a decode that returned True, or not at all. }
function PngLastColourType: Integer;
function PngLastBitDepth: Integer;
{ True when the decoded image can actually contain a non-opaque pixel: colour
  types 4 and 6 always, and 0/2/3 only when the file carried a tRNS chunk.
  A palette image is the reason this exists -- it decodes to RGBA either way,
  and only tRNS says whether any of that alpha is meaningful. }
function PngLastHasAlpha: Boolean;

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
  LastColourType: Integer;
  LastBitDepth:   Integer;
  LastHasAlpha:   Boolean;

procedure SetErr(const s: AnsiString);
begin
  LastError := s;
end;

function PngLastError: AnsiString;
begin
  Result := LastError;
end;

function PngLastColourType: Integer;
begin
  Result := LastColourType;
end;

function PngLastBitDepth: Integer;
begin
  Result := LastBitDepth;
end;

function PngLastHasAlpha: Boolean;
begin
  Result := LastHasAlpha;
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

{ A LOCAL INTEGER RENDERER, so this unit does not grow a sysutils dependency for
  two error messages. png.pas is used by the image path and by pil.pas, and
  sysutils is a large unit to pull into both for IntToStr. Named Num rather than
  IntToStr so nothing shadows the real one for a consumer that has it. }
function Num(v: Integer): AnsiString;
var neg: Boolean;
begin
  if v = 0 then begin Result := '0'; Exit; end;
  neg := v < 0;
  if neg then v := -v;
  Result := '';
  while v > 0 do
  begin
    Result := Chr(Ord('0') + (v mod 10)) + Result;
    v := v div 10;
  end;
  if neg then Result := '-' + Result;
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
  { Level 6, CPython's default, through the compressing encoder. This was
    DeflateZlibStored until 2026-09-13, which is why PNGs out of this writer were
    several times larger than they needed to be; zlib.pas's header explains the
    change. IDAT content is latitude -- any valid zlib stream decodes to the same
    pixels -- so nothing downstream of here had to change. }
  DeflateZlib(raw, z, 6);
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

{ THE FILTER OFFSET IS bpp BYTES, NOT 4, and that was the whole of what made
  this decoder RGBA-only. PNG filters run over BYTES, and the `left` neighbour a
  filter refers to is the byte one PIXEL back -- ceil(bitsPerPixel/8), floored at
  1. For 8-bit RGBA that is 4, which is why the constant worked and why nothing
  else did.

  `bpp` FLOORS AT 1 FOR THE SUB-BYTE DEPTHS, and that is the spec's rule rather
  than a rounding convenience: at 1, 2 or 4 bits a pixel is smaller than a byte,
  several pixels share one, and the filter's `left` is simply the previous byte.
  Getting this wrong is invisible on filter type 0 (None), which is what a
  hand-written fixture tends to use, and wrong on every row a real encoder
  produces. }
function UnfilterRows(const raw: TByteArray; rowBytes, height, bpp: Integer;
                      var outb: TByteArray): Boolean;
var x, y, p, dst, filter, val, left, up, upLeft: Integer;
begin
  Result := False;
  if (rowBytes <= 0) or (height <= 0) then
  begin
    SetErr('bad raw image geometry');
    Exit;
  end;
  if Length(raw) <> height * (rowBytes + 1) then
  begin
    SetErr('bad raw image length');
    Exit;
  end;
  SetLength(outb, rowBytes * height);
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
      if x >= bpp then left := outb[dst - bpp] else left := 0;
      if y > 0 then up := outb[dst - rowBytes] else up := 0;
      if (x >= bpp) and (y > 0) then upLeft := outb[dst - rowBytes - bpp]
      else upLeft := 0;
      if filter = 1 then val := (val + left) and $FF
      else if filter = 2 then val := (val + up) and $FF
      else if filter = 3 then val := (val + ((left + up) div 2)) and $FF
      else if filter = 4 then val := (val + Paeth(left, up, upLeft)) and $FF;
      outb[dst] := Byte(val);
      dst := dst + 1;
    end;
  end;
  Result := True;
end;

{ ---- sample extraction ------------------------------------------------------

  One reader for every depth, so the expansion below has no per-depth arms.
  `i` is the sample INDEX within the row, not a byte offset -- at 1/2/4 bits
  several samples share a byte, MSB first, and at 16 bits one sample spans two.

  16-BIT TAKES THE HIGH BYTE AND DOES NOT ROUND. That is what PIL does for its
  8-bit modes and what every consumer of TImage can represent; rounding would
  cost a multiply per sample to move some values by one, and TImage has nowhere
  to put the low byte anyway. Said here because "we truncate" is a choice and a
  reader comparing our output to a 16-bit-aware tool should know which. }
function SampleAt(const row: TByteArray; rowStart, i, depth: Integer): Integer;
var byteIdx, shift, mask, perByte: Integer;
begin
  if depth = 8 then
    Result := row[rowStart + i]
  else if depth = 16 then
    Result := row[rowStart + i * 2]
  else
  begin
    perByte := 8 div depth;
    byteIdx := rowStart + (i div perByte);
    shift   := 8 - depth * ((i mod perByte) + 1);
    mask    := (1 shl depth) - 1;
    Result  := (row[byteIdx] shr shift) and mask;
  end;
end;

{ A grayscale sample of `depth` bits widened to the full 0..255 range.

  THE SCALE IS 255 div maxval AND NOT A SHIFT, because the endpoints have to
  land exactly: at depth 1 the values are 0 and 255, at depth 2 they are
  0/85/170/255, at depth 4 they step by 17. A left shift gives 0 and 128 at
  depth 1 -- white would come out mid-gray, which reads as a gamma problem
  rather than as the arithmetic bug it is. }
function GrayTo8(v, depth: Integer): Integer;
begin
  if depth = 16 then Result := v
  else if depth = 8 then Result := v
  else Result := v * (255 div ((1 shl depth) - 1));
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

{ VALID (colour type, bit depth) PAIRS, straight from the spec's table. Written
  as a function rather than folded into the IHDR arm so the refusal names the
  pair it refused -- "unsupported ihdr" told a caller nothing about which of the
  five fields it had got wrong, and a palette PNG is the common case that hits
  it. }
function DepthOkFor(colourType, depth: Integer): Boolean;
begin
  if colourType = 0 then
    Result := (depth = 1) or (depth = 2) or (depth = 4) or (depth = 8) or (depth = 16)
  else if colourType = 3 then
    Result := (depth = 1) or (depth = 2) or (depth = 4) or (depth = 8)
  else if (colourType = 2) or (colourType = 4) or (colourType = 6) then
    Result := (depth = 8) or (depth = 16)
  else
    Result := False;
end;

function ChannelsOf(colourType: Integer): Integer;
begin
  if colourType = 0 then Result := 1
  else if colourType = 2 then Result := 3
  else if colourType = 3 then Result := 1
  else if colourType = 4 then Result := 2
  else Result := 4;
end;

function PngDecodeRGBA(const data: TByteArray; var img: TImage): Boolean;
var pos, chunkLen, width, height: Integer;
    depth, colourType, interlace, channels, bitsPerPixel, rowBytes, bpp: Integer;
    kind, gotCrc, wantCrc: LongWord;
    payload, raw, px, plte, trns: TByteArray;
    seenIHDR, seenIEND, seenPLTE: Boolean;
    i, x, y, rowStart, idx, sv, av: Integer;
    c: TRGBA;
    zlibErr: AnsiString;
begin
  Result := False;
  SetErr('');
  ImageFree(img);
  LastColourType := -1; LastBitDepth := 0; LastHasAlpha := False;
  if not PngSignatureValid(data) then begin SetErr('bad png signature'); Exit; end;
  pos := 8;
  width := 0; height := 0;
  depth := 0; colourType := 0; interlace := 0;
  SetLength(gIdat, 0);
  SetLength(plte, 0);
  SetLength(trns, 0);
  seenIHDR := False; seenIEND := False; seenPLTE := False;
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
      depth      := payload[8];
      colourType := payload[9];
      interlace  := payload[12];
      if not DepthOkFor(colourType, depth) then
      begin
        SetErr('unsupported colour type ' + Num(colourType) +
               ' at bit depth ' + Num(depth));
        Exit;
      end;
      if payload[10] <> 0 then begin SetErr('unsupported compression method'); Exit; end;
      if payload[11] <> 0 then begin SetErr('unsupported filter method'); Exit; end;
      { Adam7. Named rather than lumped in with the rest: see the unit header --
        decoding it as progressive yields a scrambled picture and no error. }
      if interlace <> 0 then
      begin
        SetErr('interlaced (adam7) png is not supported');
        Exit;
      end;
      LastColourType := colourType;
      LastBitDepth   := depth;
      LastHasAlpha   := (colourType = 4) or (colourType = 6);
      seenIHDR := True;
    end
    else if kind = ChunkName('P', 'L', 'T', 'E') then
    begin
      if not seenIHDR then begin SetErr('plte before ihdr'); Exit; end;
      if (chunkLen mod 3) <> 0 then begin SetErr('bad plte length'); Exit; end;
      SetLength(plte, chunkLen);
      for i := 0 to chunkLen - 1 do plte[i] := payload[i];
      seenPLTE := True;
    end
    else if kind = ChunkName('t', 'R', 'N', 'S') then
    begin
      { tRNS means three different things by colour type and is read at
        expansion time, so it is only captured here. }
      if not seenIHDR then begin SetErr('trns before ihdr'); Exit; end;
      SetLength(trns, chunkLen);
      for i := 0 to chunkLen - 1 do trns[i] := payload[i];
      if chunkLen > 0 then LastHasAlpha := True;
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
  { A palette image with no PLTE has no colours to resolve its indices against.
    The spec makes PLTE mandatory for colour type 3 and optional decoration for
    2 and 6, so only this direction is an error. }
  if (colourType = 3) and (not seenPLTE) then
  begin
    SetErr('palette png has no plte chunk');
    Exit;
  end;

  if not InflateZlib(gIdat, raw, zlibErr) then
  begin
    SetErr(zlibErr);
    Exit;
  end;

  channels     := ChannelsOf(colourType);
  bitsPerPixel := channels * depth;
  rowBytes     := (width * bitsPerPixel + 7) div 8;
  bpp          := bitsPerPixel div 8;
  if bpp < 1 then bpp := 1;

  if not UnfilterRows(raw, rowBytes, height, bpp, px) then Exit;

  { ---- expansion to 8-bit RGBA ----------------------------------------------

    ONE LOOP OVER PIXELS WITH A BRANCH PER COLOUR TYPE, rather than five loops.
    The sample reader above absorbs the depth, so what is left here is only
    which channels exist and where the alpha comes from. }
  ImageInit(img, width, height);
  for y := 0 to height - 1 do
  begin
    rowStart := y * rowBytes;
    for x := 0 to width - 1 do
    begin
      c.A := 255;
      if colourType = 0 then
      begin
        sv := GrayTo8(SampleAt(px, rowStart, x, depth), depth);
        c.R := Byte(sv); c.G := Byte(sv); c.B := Byte(sv);
        { tRNS for grayscale is ONE 16-bit sample: the single grey value that is
          fully transparent. Compared at the file's own depth, before widening,
          because the widened value is lossy at 16 bits. }
        if Length(trns) >= 2 then
        begin
          av := (Integer(trns[0]) shl 8) or Integer(trns[1]);
          if SampleAt(px, rowStart, x, depth) = av then c.A := 0;
        end;
      end
      else if colourType = 2 then
      begin
        c.R := Byte(SampleAt(px, rowStart, x * 3 + 0, depth));
        c.G := Byte(SampleAt(px, rowStart, x * 3 + 1, depth));
        c.B := Byte(SampleAt(px, rowStart, x * 3 + 2, depth));
        { tRNS for truecolour is an RGB triple, three 16-bit samples. }
        if Length(trns) >= 6 then
          if (SampleAt(px, rowStart, x * 3 + 0, depth) =
                ((Integer(trns[0]) shl 8) or Integer(trns[1]))) and
             (SampleAt(px, rowStart, x * 3 + 1, depth) =
                ((Integer(trns[2]) shl 8) or Integer(trns[3]))) and
             (SampleAt(px, rowStart, x * 3 + 2, depth) =
                ((Integer(trns[4]) shl 8) or Integer(trns[5]))) then
            c.A := 0;
      end
      else if colourType = 3 then
      begin
        idx := SampleAt(px, rowStart, x, depth);
        if (idx * 3 + 2) >= Length(plte) then
        begin
          SetErr('palette index out of range');
          Exit;
        end;
        c.R := plte[idx * 3 + 0];
        c.G := plte[idx * 3 + 1];
        c.B := plte[idx * 3 + 2];
        { tRNS for a palette is one alpha BYTE per entry, and it may be SHORTER
          than the palette -- every entry past its end is opaque. That
          shortfall is the normal case, not a malformed file: an encoder writes
          only as far as the last non-opaque entry, which is exactly what
          `optimize=True` produces for a one-transparent-colour image. }
        if idx < Length(trns) then c.A := trns[idx];
      end
      else if colourType = 4 then
      begin
        sv := GrayTo8(SampleAt(px, rowStart, x * 2 + 0, depth), depth);
        c.R := Byte(sv); c.G := Byte(sv); c.B := Byte(sv);
        c.A := Byte(SampleAt(px, rowStart, x * 2 + 1, depth));
      end
      else
      begin
        c.R := Byte(SampleAt(px, rowStart, x * 4 + 0, depth));
        c.G := Byte(SampleAt(px, rowStart, x * 4 + 1, depth));
        c.B := Byte(SampleAt(px, rowStart, x * 4 + 2, depth));
        c.A := Byte(SampleAt(px, rowStart, x * 4 + 3, depth));
      end;
      img.Pixels[y * width + x] := c;
    end;
  end;
  Result := True;
end;

end.
