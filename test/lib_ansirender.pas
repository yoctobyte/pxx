program lib_ansirender;

uses image, ansirender, ansiterm;

var
  img: TImage;
  s, expected: AnsiString;
  ESC: Char;
  HB: AnsiString;
begin
  ESC := #27;
  HB := #226#150#128;

  ImageInit(img, 2, 2);
  // Row 0: Red, Green
  ImageSetPixel(img, 0, 0, MakeRGBA(255, 0, 0, 255));
  ImageSetPixel(img, 1, 0, MakeRGBA(0, 255, 0, 255));
  // Row 1: Blue, White
  ImageSetPixel(img, 0, 1, MakeRGBA(0, 0, 255, 255));
  ImageSetPixel(img, 1, 1, MakeRGBA(255, 255, 255, 255));

  // 1. Test RenderAscii (2x2)
  s := RenderAscii(img, 2, 2);
  expected := ':+' + #10 + '.@';
  if s <> expected then
  begin
    writeln('RenderAscii failed: ', s);
    halt(1);
  end;

  // 2. Test RenderAnsiTrueColorHalfBlock (2x1 target)
  s := RenderAnsiTrueColorHalfBlock(img, 2, 1);
  expected := AnsiBgRGB(0, 0, 255) + AnsiRGB(255, 0, 0, HB) +
              AnsiBgRGB(255, 255, 255) + AnsiRGB(0, 255, 0, HB);
  if s <> expected then
  begin
    writeln('RenderAnsiTrueColorHalfBlock failed');
    halt(2);
  end;

  // 3. Test RenderAnsiTrueColorQuadrant (1x1 target)
  s := RenderAnsiTrueColorQuadrant(img, 1, 1);
  expected := AnsiBgRGB(85, 170, 170) + AnsiRGB(255, 0, 0, #226#150#152);
  if s <> expected then
  begin
    writeln('RenderAnsiTrueColorQuadrant failed');
    halt(3);
  end;

  ImageFree(img);
  writeln('OK');
end.
