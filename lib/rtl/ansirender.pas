{ SPDX-License-Identifier: Zlib }
unit ansirender;

interface

uses image;

function RenderAscii(var img: TImage; width, height: Integer): AnsiString;
function RenderAnsi256(var img: TImage; width, height: Integer): AnsiString;
function RenderAnsiTrueColorHalfBlock(var img: TImage; width, height: Integer): AnsiString;
function RenderAnsiTrueColorQuadrant(var img: TImage; width, height: Integer): AnsiString;

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

type
  TGlyph = record
    Ch: AnsiString;
    W0, W1, W2, W3: Integer;
    A, B, C, Det: Integer;
  end;

function RenderAnsiTrueColorQuadrant(var img: TImage; width, height: Integer): AnsiString;
var
  QUADRANTS: array[0..15] of AnsiString;
  GLYPHS: array[0..21] of TGlyph;
  tx, ty, k, m, wk: Integer;
  sx1, sx2, sy1, sy2: Integer;
  P: array[0..3] of TRGBA;
  minErr, err: Int64;
  nFG, nBG: Integer;
  avgAll, candFG, candBG, bestFG, bestBG: TRGBA;
  dr, dg, db: Integer;
  expR, expG, expB: Integer;
  x_R, y_R, x_G, y_G, x_B, y_B: Integer;
  D_R, D_G, D_B: Integer;
  E_R, E_G, E_B: Integer;
  bestCh: AnsiString;
  row, cell: AnsiString;
begin
  Result := '';
  if (width <= 0) or (height <= 0) or (img.Width <= 0) or (img.Height <= 0) then Exit;

  QUADRANTS[0]  := ' ';
  QUADRANTS[1]  := #226#150#152; { ▘ }
  QUADRANTS[2]  := #226#150#157; { ▝ }
  QUADRANTS[3]  := #226#150#128; { ▀ }
  QUADRANTS[4]  := #226#150#150; { ▖ }
  QUADRANTS[5]  := #226#150#140; { ▌ }
  QUADRANTS[6]  := #226#150#158; { ▞ }
  QUADRANTS[7]  := #226#150#155; { ▛ }
  QUADRANTS[8]  := #226#150#151; { ▗ }
  QUADRANTS[9]  := #226#150#154; { ▚ }
  QUADRANTS[10] := #226#150#144; { ▐ }
  QUADRANTS[11] := #226#150#156; { ▜ }
  QUADRANTS[12] := #226#150#132; { ▄ }
  QUADRANTS[13] := #226#150#153; { ▙ }
  QUADRANTS[14] := #226#150#159; { ▟ }
  QUADRANTS[15] := #226#150#136; { █ }

  for m := 0 to 15 do
  begin
    GLYPHS[m].Ch := QUADRANTS[m];
    GLYPHS[m].W0 := ((m shr 0) and 1) * 10;
    GLYPHS[m].W1 := ((m shr 1) and 1) * 10;
    GLYPHS[m].W2 := ((m shr 2) and 1) * 10;
    GLYPHS[m].W3 := ((m shr 3) and 1) * 10;

    nFG := 0; nBG := 0;
    if GLYPHS[m].W0 = 10 then nFG := nFG + 1 else nBG := nBG + 1;
    if GLYPHS[m].W1 = 10 then nFG := nFG + 1 else nBG := nBG + 1;
    if GLYPHS[m].W2 = 10 then nFG := nFG + 1 else nBG := nBG + 1;
    if GLYPHS[m].W3 = 10 then nFG := nFG + 1 else nBG := nBG + 1;

    GLYPHS[m].A := nFG * 100;
    GLYPHS[m].B := 0;
    GLYPHS[m].C := nBG * 100;
    GLYPHS[m].Det := nFG * nBG * 10000;
  end;

  // Custom glyphs for high detail textures and slopes
  GLYPHS[16].Ch := '/';
  GLYPHS[16].W0 := 2; GLYPHS[16].W1 := 8; GLYPHS[16].W2 := 8; GLYPHS[16].W3 := 2;
  GLYPHS[16].A := 136; GLYPHS[16].B := 64; GLYPHS[16].C := 136; GLYPHS[16].Det := 14400;

  GLYPHS[17].Ch := '\';
  GLYPHS[17].W0 := 8; GLYPHS[17].W1 := 2; GLYPHS[17].W2 := 2; GLYPHS[17].W3 := 8;
  GLYPHS[17].A := 136; GLYPHS[17].B := 64; GLYPHS[17].C := 136; GLYPHS[17].Det := 14400;

  GLYPHS[18].Ch := '_';
  GLYPHS[18].W0 := 2; GLYPHS[18].W1 := 2; GLYPHS[18].W2 := 8; GLYPHS[18].W3 := 8;
  GLYPHS[18].A := 136; GLYPHS[18].B := 64; GLYPHS[18].C := 136; GLYPHS[18].Det := 14400;

  GLYPHS[19].Ch := '~';
  GLYPHS[19].W0 := 8; GLYPHS[19].W1 := 8; GLYPHS[19].W2 := 2; GLYPHS[19].W3 := 2;
  GLYPHS[19].A := 136; GLYPHS[19].B := 64; GLYPHS[19].C := 136; GLYPHS[19].Det := 14400;

  GLYPHS[20].Ch := '(';
  GLYPHS[20].W0 := 8; GLYPHS[20].W1 := 2; GLYPHS[20].W2 := 8; GLYPHS[20].W3 := 2;
  GLYPHS[20].A := 136; GLYPHS[20].B := 64; GLYPHS[20].C := 136; GLYPHS[20].Det := 14400;

  GLYPHS[21].Ch := ')';
  GLYPHS[21].W0 := 2; GLYPHS[21].W1 := 8; GLYPHS[21].W2 := 2; GLYPHS[21].W3 := 8;
  GLYPHS[21].A := 136; GLYPHS[21].B := 64; GLYPHS[21].C := 136; GLYPHS[21].Det := 14400;

  for ty := 0 to height - 1 do
  begin
    row := '';
    for tx := 0 to width - 1 do
    begin
      sx1 := (2 * tx * img.Width) div (2 * width);
      sx2 := ((2 * tx + 1) * img.Width) div (2 * width);
      sy1 := (2 * ty * img.Height) div (2 * height);
      sy2 := ((2 * ty + 1) * img.Height) div (2 * height);

      P[0] := ImageGetPixel(img, sx1, sy1);
      P[1] := ImageGetPixel(img, sx2, sy1);
      P[2] := ImageGetPixel(img, sx1, sy2);
      P[3] := ImageGetPixel(img, sx2, sy2);

      for k := 0 to 3 do
      begin
        P[k].R := (P[k].R * P[k].A) div 255;
        P[k].G := (P[k].G * P[k].A) div 255;
        P[k].B := (P[k].B * P[k].A) div 255;
      end;

      avgAll.R := (P[0].R + P[1].R + P[2].R + P[3].R) div 4;
      avgAll.G := (P[0].G + P[1].G + P[2].G + P[3].G) div 4;
      avgAll.B := (P[0].B + P[1].B + P[2].B + P[3].B) div 4;

      minErr := 1000000000;
      bestFG := MakeRGBA(0, 0, 0, 255);
      bestBG := MakeRGBA(0, 0, 0, 255);
      bestCh := ' ';

      for m := 0 to 21 do
      begin
        D_R := 10 * (GLYPHS[m].W0 * P[0].R + GLYPHS[m].W1 * P[1].R + GLYPHS[m].W2 * P[2].R + GLYPHS[m].W3 * P[3].R);
        D_G := 10 * (GLYPHS[m].W0 * P[0].G + GLYPHS[m].W1 * P[1].G + GLYPHS[m].W2 * P[2].G + GLYPHS[m].W3 * P[3].G);
        D_B := 10 * (GLYPHS[m].W0 * P[0].B + GLYPHS[m].W1 * P[1].B + GLYPHS[m].W2 * P[2].B + GLYPHS[m].W3 * P[3].B);

        E_R := 10 * ((10 - GLYPHS[m].W0) * P[0].R + (10 - GLYPHS[m].W1) * P[1].R + (10 - GLYPHS[m].W2) * P[2].R + (10 - GLYPHS[m].W3) * P[3].R);
        E_G := 10 * ((10 - GLYPHS[m].W0) * P[0].G + (10 - GLYPHS[m].W1) * P[1].G + (10 - GLYPHS[m].W2) * P[2].G + (10 - GLYPHS[m].W3) * P[3].G);
        E_B := 10 * ((10 - GLYPHS[m].W0) * P[0].B + (10 - GLYPHS[m].W1) * P[1].B + (10 - GLYPHS[m].W2) * P[2].B + (10 - GLYPHS[m].W3) * P[3].B);

        if GLYPHS[m].Det <> 0 then
        begin
          x_R := (D_R * GLYPHS[m].C - E_R * GLYPHS[m].B) div GLYPHS[m].Det;
          y_R := (GLYPHS[m].A * E_R - D_R * GLYPHS[m].B) div GLYPHS[m].Det;

          x_G := (D_G * GLYPHS[m].C - E_G * GLYPHS[m].B) div GLYPHS[m].Det;
          y_G := (GLYPHS[m].A * E_G - D_G * GLYPHS[m].B) div GLYPHS[m].Det;

          x_B := (D_B * GLYPHS[m].C - E_B * GLYPHS[m].B) div GLYPHS[m].Det;
          y_B := (GLYPHS[m].A * E_B - D_B * GLYPHS[m].B) div GLYPHS[m].Det;

          candFG.R := Clamp(x_R, 0, 255);
          candBG.R := Clamp(y_R, 0, 255);
          candFG.G := Clamp(x_G, 0, 255);
          candBG.G := Clamp(y_G, 0, 255);
          candFG.B := Clamp(x_B, 0, 255);
          candBG.B := Clamp(y_B, 0, 255);
        end
        else
        begin
          if GLYPHS[m].W0 = 0 then
          begin
            candBG := avgAll;
            candFG := MakeRGBA(0, 0, 0, 255);
          end
          else
          begin
            candFG := avgAll;
            candBG := MakeRGBA(0, 0, 0, 255);
          end;
        end;

        err := 0;
        for k := 0 to 3 do
        begin
          case k of
            0: wk := GLYPHS[m].W0;
            1: wk := GLYPHS[m].W1;
            2: wk := GLYPHS[m].W2;
            3: wk := GLYPHS[m].W3;
          end;

          expR := (wk * candFG.R + (10 - wk) * candBG.R) div 10;
          expG := (wk * candFG.G + (10 - wk) * candBG.G) div 10;
          expB := (wk * candFG.B + (10 - wk) * candBG.B) div 10;

          dr := P[k].R - expR;
          dg := P[k].G - expG;
          db := P[k].B - expB;

          err := err + (dr * dr) + (dg * dg) + (db * db);
        end;

        if err < minErr then
        begin
          minErr := err;
          bestFG := candFG;
          bestBG := candBG;
          bestCh := GLYPHS[m].Ch;
        end;
      end;

      cell := AnsiBgRGB(bestBG.R, bestBG.G, bestBG.B) + AnsiRGB(bestFG.R, bestFG.G, bestFG.B, bestCh);
      row := row + cell;
    end;

    if ty < height - 1 then
      Result := Result + row + #10
    else
      Result := Result + row;
  end;
end;

end.
