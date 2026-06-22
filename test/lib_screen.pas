program lib_screen;
{ Tests the screen manager's diff renderer by asserting the EXACT minimal escape
  bytes — the point is to catch a renderer that repaints too much (or too little),
  not just that it "runs". }

uses ansiterm, screen;

var
  E: Char;
  r, exp: AnsiString;
  fails: Integer;

procedure Check(const tag: string; got, want: AnsiString);
begin
  if got = want then
    writeln(tag, '=ok')
  else
  begin
    writeln(tag, '=bad');
    fails := fails + 1;
  end;
end;

begin
  E := #27;
  fails := 0;

  { 4x2 blank screen: first render paints every cell, one pen set, one move per
    row, runs of cells share a move. }
  ScreenInitSize(4, 2);
  r := ScreenRender;
  exp := '' + E + '[1;1H' + E + '[0m' + '    ' + E + '[2;1H' + '    ';
  Check('full-paint', r, exp);

  { Change ONE cell -> the update must be just (move + pen + glyph), no repaint. }
  ScreenPutChar(2, 1, 'X');
  r := ScreenRender;
  exp := '' + E + '[2;3H' + E + '[0m' + 'X';
  Check('one-cell', r, exp);

  { Nothing changed -> empty render. }
  r := ScreenRender;
  Check('no-op', r, '');

  { Pen change: bold red 'R' on a 1x1 screen. }
  ScreenInitSize(1, 1);
  ScreenSetPen(31, COLOR_DEFAULT, ATTR_BOLD);
  ScreenPutChar(0, 0, 'R');
  r := ScreenRender;
  exp := '' + E + '[1;1H' + E + '[0m' + E + '[1m' + E + '[31m' + 'R';
  Check('pen', r, exp);

  if fails = 0 then writeln('ALL OK') else writeln('FAILS=', fails);
end.
