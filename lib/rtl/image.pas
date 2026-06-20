unit image;
{ Small byte-oriented RGBA bitmap core. Track B foundation for PNG and later
  image converters. Owns pixels in row-major order, 0-based coordinates. }

interface

type
  TRGBA = record
    R, G, B, A: Byte;
  end;

  TImage = record
    Width, Height: Integer;
    Pixels: array of TRGBA;
  end;

function MakeRGBA(r, g, b, a: Byte): TRGBA;
procedure ImageInit(var img: TImage; width, height: Integer);
procedure ImageFree(var img: TImage);
function ImagePixelCount(const img: TImage): Integer;
function ImageInBounds(const img: TImage; x, y: Integer): Boolean;
procedure ImageSetPixel(var img: TImage; x, y: Integer; c: TRGBA);
function ImageGetPixel(const img: TImage; x, y: Integer): TRGBA;
procedure ImageClear(var img: TImage; c: TRGBA);

implementation

function MakeRGBA(r, g, b, a: Byte): TRGBA;
begin
  Result.R := r;
  Result.G := g;
  Result.B := b;
  Result.A := a;
end;

procedure ImageInit(var img: TImage; width, height: Integer);
var n, i: Integer;
begin
  img.Width := width;
  img.Height := height;
  if (width <= 0) or (height <= 0) then
    n := 0
  else
    n := width * height;
  SetLength(img.Pixels, n);
  for i := 0 to n - 1 do
    img.Pixels[i] := MakeRGBA(0, 0, 0, 0);
end;

procedure ImageFree(var img: TImage);
begin
  img.Width := 0;
  img.Height := 0;
  SetLength(img.Pixels, 0);
end;

function ImagePixelCount(const img: TImage): Integer;
begin
  Result := Length(img.Pixels);
end;

function ImageInBounds(const img: TImage; x, y: Integer): Boolean;
begin
  Result := (x >= 0) and (y >= 0) and (x < img.Width) and (y < img.Height);
end;

procedure ImageSetPixel(var img: TImage; x, y: Integer; c: TRGBA);
begin
  if ImageInBounds(img, x, y) then
    img.Pixels[y * img.Width + x] := c;
end;

function ImageGetPixel(const img: TImage; x, y: Integer): TRGBA;
begin
  if ImageInBounds(img, x, y) then
    Result := img.Pixels[y * img.Width + x]
  else
    Result := MakeRGBA(0, 0, 0, 0);
end;

procedure ImageClear(var img: TImage; c: TRGBA);
var i: Integer;
begin
  for i := 0 to Length(img.Pixels) - 1 do
    img.Pixels[i] := c;
end;

end.
