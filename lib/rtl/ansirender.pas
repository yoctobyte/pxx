unit ansirender;

interface

uses image;

function RenderAscii(var img: TImage; width, height: Integer): AnsiString;
function RenderAnsi256(var img: TImage; width, height: Integer): AnsiString;
function RenderAnsiTrueColorHalfBlock(var img: TImage; width, height: Integer): AnsiString;

implementation

uses ansiterm, sysutils;

const
  ESC = #27;

function Clamp(v, min, max: Integer): Integer;
begin
  if v < min then Result := min
  else if v > max then Result := max
  else Result := v;
end;

function RgbTo256(r, g, b: Integer): Integer;
var
  qr, qg, qb: Integer;
begin
  qr := (r * 5) div 255;
  qg := (g * 5) div 255;
  qb := (b * 5) div 255;
  Result := 16 + 36 * qr + 6 * qg + qb;
end;

function RenderAscii(var img: TImage; width, height: Integer): AnsiString;
var
  RAMP: AnsiString;
  tx, ty: Integer;
  sx, sy: Integer;
  c: TRGBA;
  lum, idx: Integer;
  ch: Char;
  row: AnsiString;
begin
  Result := '';
  if (width <= 0) or (height <= 0) or (img.Width <= 0) or (img.Height <= 0) then Exit;

  RAMP := ' .:-=+*#%@';

  for ty := 0 to height - 1 do
  begin
    row := '';
    for tx := 0 to width - 1 do
    begin
      sx := (tx * img.Width) div width;
      sy := (ty * img.Height) div height;
      c := ImageGetPixel(img, sx, sy);
      c.R := (c.R * c.A) div 255;
      c.G := (c.G * c.A) div 255;
      c.B := (c.B * c.A) div 255;
      lum := (c.R * 299 + c.G * 587 + c.B * 114) div 1000;
      idx := (lum * 9) div 255;
      idx := Clamp(idx, 0, 9);
      ch := RAMP[idx + 1];
      row := row + ch;
    end;
    if ty < height - 1 then
      Result := Result + row + #10
    else
      Result := Result + row;
  end;
end;

function RenderAnsi256(var img: TImage; width, height: Integer): AnsiString;
var
  RAMP: AnsiString;
  tx, ty: Integer;
  sx, sy: Integer;
  c: TRGBA;
  lum, idx, colorIdx: Integer;
  ch: Char;
  row: AnsiString;
  cell: AnsiString;
begin
  Result := '';
  if (width <= 0) or (height <= 0) or (img.Width <= 0) or (img.Height <= 0) then Exit;

  RAMP := ' .:-=+*#%@';

  for ty := 0 to height - 1 do
  begin
    row := '';
    for tx := 0 to width - 1 do
    begin
      sx := (tx * img.Width) div width;
      sy := (ty * img.Height) div height;
      c := ImageGetPixel(img, sx, sy);
      c.R := (c.R * c.A) div 255;
      c.G := (c.G * c.A) div 255;
      c.B := (c.B * c.A) div 255;
      lum := (c.R * 299 + c.G * 587 + c.B * 114) div 1000;
      idx := (lum * 9) div 255;
      idx := Clamp(idx, 0, 9);
      ch := RAMP[idx + 1];
      colorIdx := RgbTo256(c.R, c.G, c.B);
      cell := '' + ESC + '[38;5;' + IntToStr(colorIdx) + 'm' + ch + ESC + '[0m';
      row := row + cell;
    end;
    if ty < height - 1 then
      Result := Result + row + #10
    else
      Result := Result + row;
  end;
end;

function RenderAnsiTrueColorHalfBlock(var img: TImage; width, height: Integer): AnsiString;
var
  tx, ty: Integer;
  sx1, sy1, sx2, sy2: Integer;
  c1, c2: TRGBA;
  row: AnsiString;
  cell: AnsiString;
  HALF_BLOCK: AnsiString;
begin
  Result := '';
  if (width <= 0) or (height <= 0) or (img.Width <= 0) or (img.Height <= 0) then Exit;

  HALF_BLOCK := #226#150#128;

  for ty := 0 to height - 1 do
  begin
    row := '';
    for tx := 0 to width - 1 do
    begin
      sx1 := (tx * img.Width) div width;
      sy1 := ((2 * ty) * img.Height) div (2 * height);
      sx2 := (tx * img.Width) div width;
      sy2 := ((2 * ty + 1) * img.Height) div (2 * height);

      c1 := ImageGetPixel(img, sx1, sy1);
      c2 := ImageGetPixel(img, sx2, sy2);

      c1.R := (c1.R * c1.A) div 255;
      c1.G := (c1.G * c1.A) div 255;
      c1.B := (c1.B * c1.A) div 255;

      c2.R := (c2.R * c2.A) div 255;
      c2.G := (c2.G * c2.A) div 255;
      c2.B := (c2.B * c2.A) div 255;

      cell := AnsiBgRGB(c2.R, c2.G, c2.B) + AnsiRGB(c1.R, c1.G, c1.B, HALF_BLOCK);
      row := row + cell;
    end;
    if ty < height - 1 then
      Result := Result + row + #10
    else
      Result := Result + row;
  end;
end;

end.
