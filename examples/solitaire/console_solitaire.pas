program console_solitaire;
{ Console Klondike solitaire — the tested `klondike` engine rendered with the
  `screen` TUI manager (lib/rtl/screen.pas), no GUI. Keyboard play:
    arrows  move the column cursor
    space   act on the cursor pile: stock = draw; else pick a source, then a
            destination (the largest legal face-up run moves)
    u undo   a auto-to-foundation   n new game   q / Esc quit
  Reads keys through ScreenWaitKey, so piped input drives it headlessly and EOF
  (KEY_NONE) quits cleanly — used by the scripted smoke. }

uses screen, sysutils, klondike;

const
  N_CURSOR = 13;   { 0 stock, 1 waste, 2..5 foundations, 6..12 tableau }
  TOP_Y    = 2;
  TAB_Y    = 5;

var
  cursor: Integer;
  selected: Integer;
  moveCount: Integer;
  running: Boolean;

function CursorPile(c: Integer): Integer;
begin
  if c = 0 then CursorPile := P_STOCK
  else if c = 1 then CursorPile := P_WASTE
  else if c <= 5 then CursorPile := P_FOUND + (c - 2)
  else CursorPile := P_TAB + (c - 6);
end;

function PileCol(c: Integer): Integer;
begin
  { x position of each cursor slot }
  case c of
    0: PileCol := 2;
    1: PileCol := 8;
    2: PileCol := 22;
    3: PileCol := 28;
    4: PileCol := 34;
    5: PileCol := 40;
  else
    PileCol := 2 + (c - 6) * 7;
  end;
end;

function RankCh(r: Integer): Char;
begin
  case r of
    1:  RankCh := 'A';
    10: RankCh := 'T';
    11: RankCh := 'J';
    12: RankCh := 'Q';
    13: RankCh := 'K';
  else
    RankCh := Chr(Ord('0') + r);
  end;
end;

function SuitCh(s: Integer): Char;
begin
  case s of
    0: SuitCh := 'C';
    1: SuitCh := 'D';
    2: SuitCh := 'H';
  else SuitCh := 'S';
  end;
end;

{ Draw a single card cell. mode: 0 normal, 1 cursor, 2 selected source. }
procedure DrawCardCell(x, y, suit, rank: Integer; faceUp: Boolean; mode: Integer);
var fg, bg: Integer; lbl: AnsiString;
begin
  bg := COLOR_DEFAULT;
  if mode = 1 then bg := COLOR_BLUE
  else if mode = 2 then bg := COLOR_GREEN;
  if faceUp then
  begin
    if IsRed(suit) then fg := COLOR_BRIGHT_RED else fg := COLOR_BRIGHT_WHITE;
    lbl := RankCh(rank) + SuitCh(suit);
  end
  else
  begin
    fg := COLOR_BRIGHT_BLACK;
    lbl := '##';
  end;
  ScreenSetPen(fg, bg, ATTR_NONE);
  ScreenWrite(x, y, ' ' + lbl + ' ');
end;

procedure DrawEmptyCell(x, y, mode: Integer);
var bg: Integer;
begin
  bg := COLOR_DEFAULT;
  if mode = 1 then bg := COLOR_BLUE
  else if mode = 2 then bg := COLOR_GREEN;
  ScreenSetPen(COLOR_BRIGHT_BLACK, bg, ATTR_NONE);
  ScreenWrite(x, y, ' .. ');
end;

function CellMode(p: Integer): Integer;
begin
  if p = selected then CellMode := 2
  else if p = CursorPile(cursor) then CellMode := 1
  else CellMode := 0;
end;

procedure DrawTopPile(c: Integer);
var p, x, n: Integer;
begin
  p := CursorPile(c);
  x := PileCol(c);
  n := PileCount(p);
  if n = 0 then DrawEmptyCell(x, TOP_Y, CellMode(p))
  else DrawCardCell(x, TOP_Y, CardSuit(p, n - 1), CardRank(p, n - 1),
                    CardFaceUp(p, n - 1), CellMode(p));
end;

procedure DrawTableau(c: Integer);
var p, x, y, i, n: Integer;
begin
  p := CursorPile(c);
  x := PileCol(c);
  n := PileCount(p);
  if n = 0 then
  begin
    DrawEmptyCell(x, TAB_Y, CellMode(p));
    Exit;
  end;
  y := TAB_Y;
  for i := 0 to n - 1 do
  begin
    DrawCardCell(x, y, CardSuit(p, i), CardRank(p, i), CardFaceUp(p, i), CellMode(p));
    y := y + 1;
  end;
end;

procedure Render;
var c: Integer; st: AnsiString;
begin
  ScreenSetPen(COLOR_DEFAULT, COLOR_DEFAULT, ATTR_NONE);
  ScreenClear;
  ScreenSetPen(COLOR_BRIGHT_YELLOW, COLOR_DEFAULT, ATTR_BOLD);
  ScreenWrite(2, 0, 'Klondike Solitaire');
  ScreenSetPen(COLOR_BRIGHT_BLACK, COLOR_DEFAULT, ATTR_NONE);
  ScreenWrite(2, 1, 'Stock Waste        Foundations');
  for c := 0 to 5 do DrawTopPile(c);
  for c := 6 to 12 do DrawTableau(c);

  if IsWon then st := 'YOU WIN!  moves=' + IntToStr(moveCount)
  else st := 'moves=' + IntToStr(moveCount) + '   [<- ->] move  [space] act  [u]ndo [a]uto [n]ew [q]uit';
  ScreenSetPen(COLOR_BRIGHT_WHITE, COLOR_DEFAULT, ATTR_NONE);
  ScreenWrite(2, ScreenRows - 1, st);
  ScreenRefresh;
end;

function FaceUpRun(p: Integer): Integer;
var n, k: Integer;
begin
  n := PileCount(p);
  k := 0;
  while (k < n) and CardFaceUp(p, n - 1 - k) do k := k + 1;
  FaceUpRun := k;
end;

procedure MoveBest(src, dst: Integer);
var k: Integer; done: Boolean;
begin
  done := False;
  k := FaceUpRun(src);
  while (k >= 1) and (not done) do
  begin
    if TryMove(src, dst, k) then begin moveCount := moveCount + 1; done := True; end;
    k := k - 1;
  end;
end;

procedure ActOnCursor;
var p: Integer;
begin
  p := CursorPile(cursor);
  if p = P_STOCK then
  begin
    DrawStock;
    selected := -1;
  end
  else if selected < 0 then
    selected := p
  else
  begin
    if p <> selected then MoveBest(selected, p);
    selected := -1;
  end;
end;

procedure AutoAll;
var moved: Boolean; i: Integer;
begin
  repeat
    moved := False;
    if AutoFoundation(P_WASTE) then begin moved := True; moveCount := moveCount + 1; end;
    for i := 0 to 6 do
      if AutoFoundation(P_TAB + i) then begin moved := True; moveCount := moveCount + 1; end;
  until not moved;
end;

var key: Integer;
begin
  cursor := 0;
  selected := -1;
  moveCount := 0;
  NewGame(1);

  ScreenInitSize(64, 24);
  ScreenStart;
  running := True;
  while running do
  begin
    Render;
    key := ScreenWaitKey;
    if (key = KEY_NONE) or (key = Ord('q')) or (key = KEY_ESC) then running := False
    else if key = KEY_LEFT then begin cursor := cursor - 1; if cursor < 0 then cursor := N_CURSOR - 1; end
    else if key = KEY_RIGHT then begin cursor := cursor + 1; if cursor >= N_CURSOR then cursor := 0; end
    else if (key = Ord(' ')) or (key = 13) or (key = 10) then ActOnCursor
    else if key = Ord('u') then begin Undo; selected := -1; end
    else if key = Ord('a') then AutoAll
    else if key = Ord('n') then begin NewGame(Random(100000) + 1); selected := -1; moveCount := 0; end;
  end;
  ScreenEnd;

  writeln;   { flush the escape line so the summary lands clean for tail -1 }
  writeln('moves=', moveCount, ' won=', IsWon);
end.
