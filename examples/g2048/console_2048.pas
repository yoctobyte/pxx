{ SPDX-License-Identifier: 0BSD }
program console_2048;
{ Console 2048 — the tested `g2048` engine rendered with the `screen` TUI
  manager. Arrow keys slide/merge; a tile spawns each move; score accrues; win
  at 2048, "game over" when stuck. q/Esc quit. Keys via ScreenWaitKey, so piped
  input drives it headlessly (EOF quits) for the scripted smoke. }

uses screen, sysutils, g2048;

const
  CELL_W = 6;
  CELL_H = 3;
  ORIGIN_X = 2;
  ORIGIN_Y = 2;

function TileColor(v: Integer): Integer;
begin
  case v of
    0:    TileColor := COLOR_BRIGHT_BLACK;
    2:    TileColor := COLOR_WHITE;
    4:    TileColor := COLOR_BRIGHT_YELLOW;
    8:    TileColor := COLOR_BRIGHT_RED;
    16:   TileColor := COLOR_BRIGHT_MAGENTA;
    32:   TileColor := COLOR_BRIGHT_GREEN;
    64:   TileColor := COLOR_BRIGHT_CYAN;
    128:  TileColor := COLOR_BRIGHT_BLUE;
  else
    TileColor := COLOR_BRIGHT_WHITE;
  end;
end;

procedure DrawTile(r, c: Integer);
var v, cx, cy, px: Integer; lbl: AnsiString;
begin
  v := CellAt(r, c);
  cx := ORIGIN_X + c * (CELL_W + 1);
  cy := ORIGIN_Y + r * (CELL_H + 1);
  ScreenSetPen(TileColor(v), COLOR_DEFAULT, ATTR_NONE);
  ScreenBox(cx, cy, CELL_W, CELL_H);
  if v = 0 then lbl := '.' else lbl := IntToStr(v);
  px := cx + (CELL_W - Length(lbl)) div 2;
  if v >= 8 then ScreenSetPen(TileColor(v), COLOR_DEFAULT, ATTR_BOLD)
  else ScreenSetPen(TileColor(v), COLOR_DEFAULT, ATTR_NONE);
  ScreenWrite(px, cy + 1, lbl);
end;

procedure Render;
var r, c: Integer; st: AnsiString;
begin
  ScreenSetPen(COLOR_DEFAULT, COLOR_DEFAULT, ATTR_NONE);
  ScreenClear;
  ScreenSetPen(COLOR_BRIGHT_YELLOW, COLOR_DEFAULT, ATTR_BOLD);
  ScreenWrite(ORIGIN_X, 0, '2048');
  for r := 0 to 3 do
    for c := 0 to 3 do DrawTile(r, c);
  if HasWon2048 then st := 'YOU WIN!  score=' + IntToStr(Score2048)
  else if IsOver2048 then st := 'GAME OVER  score=' + IntToStr(Score2048)
  else st := 'score=' + IntToStr(Score2048) + '   arrows slide  q quit';
  ScreenSetPen(COLOR_BRIGHT_WHITE, COLOR_DEFAULT, ATTR_NONE);
  ScreenWrite(ORIGIN_X, ORIGIN_Y + 4 * (CELL_H + 1) + 1, st);
  ScreenRefresh;
end;

var key, dir: Integer; running: Boolean;
begin
  NewGame2048(1);
  ScreenInitSize(48, 24);
  ScreenStart;
  running := True;
  while running do
  begin
    Render;
    key := ScreenWaitKey;
    dir := -1;
    if (key = KEY_NONE) or (key = Ord('q')) or (key = KEY_ESC) then running := False
    else if key = KEY_LEFT then dir := 0
    else if key = KEY_RIGHT then dir := 1
    else if key = KEY_UP then dir := 2
    else if key = KEY_DOWN then dir := 3
    else if key = Ord('n') then NewGame2048(Random(100000) + 1);
    if dir >= 0 then
    begin
      if Move2048(dir) and IsOver2048 then ;   { keep rendering; status shows over }
    end;
  end;
  ScreenEnd;

  writeln;
  writeln('score=', Score2048, ' over=', IsOver2048);
end.
