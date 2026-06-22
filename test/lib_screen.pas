program lib_screen;
{ Tests the screen manager's diff renderer by asserting the EXACT minimal escape
  bytes — the point is to catch a renderer that repaints too much (or too little),
  not just that it "runs". }

uses ansiterm, screen;

var
  E: Char;
  r, exp, k: AnsiString;
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

procedure CheckKey(const tag: string; got, want: Integer);
begin
  if got = want then
    writeln(tag, '=ok')
  else
  begin
    writeln(tag, '=bad ', got);
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

  { --- draw primitives: after a blank paint, a draw emits only its cells --- }
  ScreenInitSize(5, 3);
  r := ScreenRender;                 { paint blank, front == back }
  ScreenHLine(1, 1, 3, '=');
  r := ScreenRender;
  exp := '' + E + '[2;2H' + E + '[0m' + '===';
  Check('hline', r, exp);

  ScreenInitSize(3, 2);
  r := ScreenRender;
  ScreenFillRect(0, 0, 2, 2, '#');
  r := ScreenRender;
  exp := '' + E + '[1;1H' + E + '[0m' + '##' + E + '[2;1H' + '##';
  Check('fillrect', r, exp);

  { clip: a 5x5 fill clipped to a 2x2 region at offset (2,1) writes only the
    four in-region cells (clip-local coords, translated). }
  ScreenInitSize(6, 3);
  r := ScreenRender;
  ScreenSetClip(2, 1, 2, 2);
  ScreenFillRect(0, 0, 5, 5, '#');
  r := ScreenRender;
  exp := '' + E + '[2;3H' + E + '[0m' + '##' + E + '[3;3H' + '##';
  Check('clip', r, exp);

  { --- composition: a box + text lays out as the expected ASCII picture --- }
  ScreenInitSize(6, 4);
  ScreenBox(0, 0, 6, 4);
  ScreenWrite(1, 1, 'Hi');
  Check('scene0', ScreenDumpRow(0), '+----+');
  Check('scene1', ScreenDumpRow(1), '|Hi  |');
  Check('scene2', ScreenDumpRow(2), '|    |');
  Check('scene3', ScreenDumpRow(3), '+----+');

  { --- two clipped panels side by side + a title: the panel system composes --- }
  ScreenInitSize(13, 5);
  ScreenWrite(0, 0, 'Title');
  ScreenSetClip(0, 1, 6, 4);
  ScreenBox(0, 0, 6, 4);
  ScreenWrite(1, 1, 'L');
  ScreenSetClip(7, 1, 6, 4);
  ScreenBox(0, 0, 6, 4);
  ScreenWrite(1, 1, 'R');
  ScreenResetClip;
  Check('lay0', ScreenDumpRow(0), 'Title        ');
  Check('lay1', ScreenDumpRow(1), '+----+ +----+');
  Check('lay2', ScreenDumpRow(2), '|L   | |R   |');
  Check('lay3', ScreenDumpRow(3), '|    | |    |');
  Check('lay4', ScreenDumpRow(4), '+----+ +----+');

  { --- key decoder (pure, exact). Sequences go through a variable first to
    sidestep bug-ansistring-concat-arg-static-bloat (a concat expression passed
    straight as an arg reserves ~8 MB of BSS per call site). --- }
  k := 'q';            CheckKey('k-char',  ScreenDecodeKey(k), 113);
  k := '' + #13;       CheckKey('k-enter', ScreenDecodeKey(k), 13);
  k := '' + #9;        CheckKey('k-tab',   ScreenDecodeKey(k), 9);
  k := '' + #127;      CheckKey('k-bs',    ScreenDecodeKey(k), 127);
  k := '' + E;         CheckKey('k-esc',   ScreenDecodeKey(k), KEY_ESC);
  k := '' + E + '[A';  CheckKey('k-up',    ScreenDecodeKey(k), KEY_UP);
  k := '' + E + '[B';  CheckKey('k-down',  ScreenDecodeKey(k), KEY_DOWN);
  k := '' + E + '[C';  CheckKey('k-right', ScreenDecodeKey(k), KEY_RIGHT);
  k := '' + E + '[D';  CheckKey('k-left',  ScreenDecodeKey(k), KEY_LEFT);
  k := '' + E + '[H';  CheckKey('k-home',  ScreenDecodeKey(k), KEY_HOME);
  k := '' + E + '[F';  CheckKey('k-end',   ScreenDecodeKey(k), KEY_END);
  k := '' + E + 'OA';  CheckKey('k-ss3up', ScreenDecodeKey(k), KEY_UP);
  k := '' + E + '[3~'; CheckKey('k-del',   ScreenDecodeKey(k), KEY_DEL);
  k := '' + E + '[5~'; CheckKey('k-pgup',  ScreenDecodeKey(k), KEY_PGUP);
  k := '' + E + '[6~'; CheckKey('k-pgdn',  ScreenDecodeKey(k), KEY_PGDN);
  k := '' + E + '[2~'; CheckKey('k-ins',   ScreenDecodeKey(k), KEY_INS);
  k := '' + E + '[1~'; CheckKey('k-home1', ScreenDecodeKey(k), KEY_HOME);
  k := '' + E + '[Z';  CheckKey('k-junk',  ScreenDecodeKey(k), KEY_UNKNOWN);

  if fails = 0 then writeln('ALL OK') else writeln('FAILS=', fails);
end.
