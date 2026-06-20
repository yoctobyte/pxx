program lib_png;
{ Unit test for RTL image/png. Encodes a tiny RGBA image to valid PNG bytes,
  decodes it back, and verifies CRC rejection. }

uses image, png;

var
  img, outImg: TImage;
  bytes, bad: TByteArray;
  c: TRGBA;
  i: Integer;
begin
  ImageInit(img, 2, 2);
  ImageSetPixel(img, 0, 0, MakeRGBA(255, 0, 0, 255));
  ImageSetPixel(img, 1, 0, MakeRGBA(0, 255, 0, 128));
  ImageSetPixel(img, 0, 1, MakeRGBA(0, 0, 255, 64));
  ImageSetPixel(img, 1, 1, MakeRGBA(255, 255, 255, 0));

  bytes := PngEncodeRGBA(img);
  writeln(Length(bytes));
  writeln(bytes[0], ' ', bytes[1], ' ', bytes[2], ' ', bytes[3]);
  writeln(PngSignatureValid(bytes));

  if PngDecodeRGBA(bytes, outImg) then
  begin
    writeln(outImg.Width, 'x', outImg.Height);
    for i := 0 to ImagePixelCount(outImg) - 1 do
    begin
      c := outImg.Pixels[i];
      writeln(c.R, ',', c.G, ',', c.B, ',', c.A);
    end;
  end
  else
    writeln('decode=', PngLastError);

  SetLength(bad, Length(bytes));
  for i := 0 to Length(bytes) - 1 do bad[i] := bytes[i];
  bad[40] := bad[40] xor 1;
  writeln(PngDecodeRGBA(bad, outImg));
  writeln(PngLastError);
end.
