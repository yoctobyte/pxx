{ SPDX-License-Identifier: 0BSD }
program menudemo;
{ A real interactive TUI demo exercising the whole library end to end: full-screen
  mode (ScreenStart = raw + alt buffer + hidden cursor), a redraw/refresh loop, and
  blocking key input (ScreenWaitKey) decoded to navigation. Arrow keys move the
  selection, Enter chooses, 'q' quits. On exit it restores the terminal and prints
  the chosen item — so it is also a scriptable full-stack test:

    printf '\033[B\033[B\r' | menudemo   ->  selected=Quit }

uses screen, menu;

var
  items: array[0..2] of AnsiString;
  sel, k, i: Integer;
  running: Boolean;
begin
  items[0] := 'Open';
  items[1] := 'Save';
  items[2] := 'Quit';
  sel := 0;

  ScreenStart;
  running := True;
  while running do
  begin
    ScreenClear;
    ScreenWrite(2, 1, 'Choose (arrows, Enter, q):');
    for i := 0 to 2 do
    begin
      if i = sel then ScreenSetPen(COLOR_DEFAULT, COLOR_DEFAULT, ATTR_REVERSE)
      else ScreenSetPen(COLOR_DEFAULT, COLOR_DEFAULT, ATTR_NONE);
      ScreenWrite(4, 3 + i, items[i]);
    end;
    ScreenSetPen(COLOR_DEFAULT, COLOR_DEFAULT, ATTR_NONE);
    ScreenRefresh;

    k := ScreenWaitKey;
    if (k = Ord('q')) or (k = 13) or (k = KEY_NONE) then
      running := False
    else
      sel := MenuNavigate(3, sel, k, True);
  end;
  ScreenEnd;

  { A newline terminates the (newline-free) escape output so the result lands on
    its own final line — lets the scripted test read it with `tail -1`. }
  writeln;
  writeln('selected=', items[sel]);
end.
