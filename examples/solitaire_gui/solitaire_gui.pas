{ SPDX-License-Identifier: 0BSD }
program solitaire_gui;
{ Klondike solitaire — PCL/GTK3 GUI over the tested `klondike` engine. The board
  is custom-drawn in TPaintBox.OnPaint and played by dragging cards: press a card
  (OnMouseDown) to pick it up together with the run stacked on top of it, release
  on a destination (OnMouseUp) to drop; an illegal drop leaves everything where it
  was. Press the stock to draw. Commands live on a menu bar (Game / Help); the
  move counter and win state show in the title bar. Keyboard: n=new, u=undo,
  a=auto, d/space=draw, q=quit.

  Layout (card size, spacing, hit-test regions) is recomputed whenever the window
  resizes, so the board scales to fill the window. Suit pips are real Unicode
  glyphs (DejaVu Sans has them; the generic 'Sans' the cairo toy-text API resolves
  does not — it renders tofu, so the font name is load-bearing here).

  `--smoke`: drive the handlers headlessly (draw, drag, key, resize), assert a
  stock press draws, print SMOKE OK and exit (no event loop).

  `--gui-smoke`: map the REAL window, run the REAL event loop, self-quit from a
  g_timeout (exercised under xvfb in CI); prints GUI SMOKE OK. }

{$define PXX_MANAGED_STRING}

uses gtk3, controls, stdctrls, forms, extctrls, graphics, menus, sysutils, klondike;

const
  COL_TABLE = $00206018;   { felt green, $00BBGGRR }
  COL_BACK  = $00903018;   { card back }
  COL_BACK2 = $00C05828;   { card back inner }
  COL_EMPTY = $00305828;   { empty pile slot }
  COL_GRAY  = $00A0A0A0;
  CARD_FONT = 'DejaVu Sans';

type
  THandler = class
    selPile: Integer;      { pile being dragged from, -1 = none }
    selStart: Integer;     { index of the lowest grabbed card in that pile }
    moveCount: Integer;
    { responsive layout, recomputed on resize }
    boardW, boardH, cardW, cardH, colStep, marginX, topY, tabY, fanUp, fanDown: Integer;
    PaintBox: TPaintBox;
    Form: TForm;
    constructor Create(APaint: TPaintBox; AForm: TForm);
    procedure RecalcLayout(w, h: Integer);
    function PileX(p: Integer): Integer;
    function PileY(p: Integer): Integer;
    function CardTop(p, i: Integer): Integer;
    procedure DrawCard(Canvas: TCanvas; x, y, suit, rank: Integer; faceUp: Boolean);
    procedure DrawPile(Canvas: TCanvas; p: Integer; fanned: Boolean);
    procedure OnPaint(Sender: TControl; Canvas: TCanvas);
    procedure Refresh;
    function FaceUpRun(p: Integer): Integer;
    function HitPile(x, y: Integer): Integer;
    function HitCard(p, x, y: Integer): Integer;
    procedure DoMouseDown(Sender: TControl; Button, X, Y: Integer);
    procedure DoMouseUp(Sender: TControl; Button, X, Y: Integer);
    procedure DoKeyDown(Sender: TControl; KeyCode: Integer);
    procedure DoResize(Sender: TControl; Width, Height: Integer);
    procedure OnFormResize(Sender: TControl; Width, Height: Integer);
    procedure DoNew(Sender: TObject);
    procedure DoDraw(Sender: TObject);
    procedure DoUndo(Sender: TObject);
    procedure DoAuto(Sender: TObject);
    procedure DoQuit(Sender: TObject);
    procedure DoHelp(Sender: TObject);
  end;

function RankStr(r: Integer): string;
begin
  if r = 1 then RankStr := 'A'
  else if r = 10 then RankStr := '10'
  else if r = 11 then RankStr := 'J'
  else if r = 12 then RankStr := 'Q'
  else if r = 13 then RankStr := 'K'
  else RankStr := IntToStr(r);
end;

{ Unicode suit pip (UTF-8). engine suits: 0=clubs 1=diamonds 2=hearts 3=spades. }
function SuitCh(s: Integer): string;
begin
  if s = 0 then SuitCh := #$E2#$99#$A3        { U+2663 black club }
  else if s = 1 then SuitCh := #$E2#$99#$A6   { U+2666 black diamond }
  else if s = 2 then SuitCh := #$E2#$99#$A5   { U+2665 black heart }
  else SuitCh := #$E2#$99#$A0;                { U+2660 black spade }
end;

constructor THandler.Create(APaint: TPaintBox; AForm: TForm);
begin
  PaintBox := APaint;
  Form := AForm;
  selPile := -1;
  selStart := -1;
  moveCount := 0;
  RecalcLayout(700, 560);
  NewGame(1);
end;

{ Recompute card size / spacing / hit-test geometry for a w x h board. The 7
  tableau columns fill the width; everything else derives from the column step. }
procedure THandler.RecalcLayout(w, h: Integer);
begin
  if w < 420 then w := 420;
  if h < 420 then h := 420;
  boardW := w; boardH := h;
  colStep := w div 7;
  cardW := colStep - 10;
  if cardW < 40 then cardW := 40;
  cardH := cardW * 7 div 5;
  marginX := (w - colStep * 7) div 2 + 5;
  topY := 12;
  tabY := topY + cardH + 18;
  fanUp := cardH div 4;    if fanUp < 14 then fanUp := 14;
  fanDown := cardH div 14; if fanDown < 4 then fanDown := 4;
end;

{ column index of each pile: stock 0, waste 1, foundations 3..6, tableau 0..6
  (foundations share the top row, tableau the lower one). }
function THandler.PileX(p: Integer): Integer;
var col: Integer;
begin
  if p = P_STOCK then col := 0
  else if p = P_WASTE then col := 1
  else if (p >= P_FOUND) and (p < P_FOUND + N_FOUND) then col := 3 + (p - P_FOUND)
  else col := p - P_TAB;
  PileX := marginX + col * colStep;
end;

function THandler.PileY(p: Integer): Integer;
begin
  if (p >= P_TAB) then PileY := tabY else PileY := topY;
end;

{ Top Y of card index i in pile p (accounts for the fan). }
function THandler.CardTop(p, i: Integer): Integer;
var k, cy: Integer;
begin
  cy := PileY(p);
  if p < P_TAB then begin CardTop := cy; Exit; end;   { top-row piles: no fan }
  for k := 0 to i - 1 do
    if CardFaceUp(p, k) then cy := cy + fanUp else cy := cy + fanDown;
  CardTop := cy;
end;

procedure THandler.DrawCard(Canvas: TCanvas; x, y, suit, rank: Integer; faceUp: Boolean);
var fs, cs: Integer; lbl, pip: string;
begin
  Canvas.Pen.Color := clBlack;
  Canvas.Pen.Width := 1;
  if faceUp then
  begin
    Canvas.Brush.Color := clWhite;
    Canvas.Rectangle(x, y, x + cardW, y + cardH);
    if IsRed(suit) then Canvas.Font.Color := clRed else Canvas.Font.Color := clBlack;
    Canvas.Font.Name := CARD_FONT;
    pip := SuitCh(suit);
    lbl := RankStr(rank) + pip;
    { corner index }
    fs := cardH div 7; if fs < 9 then fs := 9;
    Canvas.Font.Size := fs;
    Canvas.TextOut(x + 4, y + 2, lbl);
    { big centre pip }
    cs := cardH div 3; if cs < 12 then cs := 12;
    Canvas.Font.Size := cs;
    Canvas.TextOut(x + cardW div 2 - cs div 2, y + cardH div 2 - cs * 2 div 3, pip);
  end
  else
  begin
    Canvas.Brush.Color := COL_BACK;
    Canvas.Rectangle(x, y, x + cardW, y + cardH);
    Canvas.Pen.Color := COL_BACK2;
    Canvas.Brush.Color := COL_BACK2;
    Canvas.Rectangle(x + 5, y + 5, x + cardW - 5, y + cardH - 5);
  end;
end;

procedure THandler.DrawPile(Canvas: TCanvas; p: Integer; fanned: Boolean);
var i, n, cy, dy, x, y: Integer;
begin
  x := PileX(p); y := PileY(p);
  n := PileCount(p);
  if n = 0 then
  begin
    Canvas.Brush.Color := COL_EMPTY;
    Canvas.Pen.Color := COL_GRAY;
    Canvas.Rectangle(x, y, x + cardW, y + cardH);
    Exit;
  end;
  if not fanned then
  begin
    DrawCard(Canvas, x, y, CardSuit(p, n - 1), CardRank(p, n - 1), CardFaceUp(p, n - 1));
    Exit;
  end;
  cy := y;
  for i := 0 to n - 1 do
  begin
    DrawCard(Canvas, x, cy, CardSuit(p, i), CardRank(p, i), CardFaceUp(p, i));
    if CardFaceUp(p, i) then dy := fanUp else dy := fanDown;
    cy := cy + dy;
  end;
end;

procedure THandler.OnPaint(Sender: TControl; Canvas: TCanvas);
var c, x, y, yb: Integer;
begin
  if Canvas = nil then Exit;
  Canvas.Brush.Color := COL_TABLE;
  Canvas.Pen.Color := COL_TABLE;
  Canvas.Rectangle(0, 0, boardW, boardH);

  DrawPile(Canvas, P_STOCK, False);
  DrawPile(Canvas, P_WASTE, False);
  for c := 0 to N_FOUND - 1 do DrawPile(Canvas, P_FOUND + c, False);
  for c := 0 to N_TAB - 1 do DrawPile(Canvas, P_TAB + c, True);

  { highlight only the grabbed run — a stroked outline (Rectangle would fill and
    erase the card faces; the pen-only path leaves them visible). }
  if selPile >= 0 then
  begin
    Canvas.Pen.Color := clYellow;
    Canvas.Pen.Width := 3;
    x := PileX(selPile);
    y := CardTop(selPile, selStart);
    yb := CardTop(selPile, PileCount(selPile) - 1) + cardH;
    Canvas.MoveTo(x - 1, y - 1);
    Canvas.LineTo(x + cardW + 1, y - 1);
    Canvas.LineTo(x + cardW + 1, yb + 1);
    Canvas.LineTo(x - 1, yb + 1);
    Canvas.LineTo(x - 1, y - 1);
  end;
end;

procedure THandler.Refresh;
begin
  if Form <> nil then
  begin
    if IsWon then Form.Caption := 'Klondike — You win!  (' + IntToStr(moveCount) + ' moves)'
    else Form.Caption := 'Klondike — Moves: ' + IntToStr(moveCount);
  end;
  if PaintBox <> nil then PaintBox.Invalidate;
end;

function THandler.FaceUpRun(p: Integer): Integer;
var n, k: Integer;
begin
  n := PileCount(p);
  k := 0;
  while (k < n) and CardFaceUp(p, n - 1 - k) do k := k + 1;
  FaceUpRun := k;
end;

{ Which pile is at (x,y)? Inverse of the layout. -1 = none. }
function THandler.HitPile(x, y: Integer): Integer;
var col, off: Integer;
begin
  HitPile := -1;
  if colStep <= 0 then Exit;
  col := (x - marginX) div colStep;
  if col < 0 then Exit;
  off := (x - marginX) - col * colStep;
  if off >= cardW then Exit;            { in the gap between columns }
  if (y >= topY) and (y < topY + cardH) then
  begin
    if col = 0 then HitPile := P_STOCK
    else if col = 1 then HitPile := P_WASTE
    else if (col >= 3) and (col <= 6) then HitPile := P_FOUND + (col - 3);
  end
  else if (y >= tabY) and (col >= 0) and (col < N_TAB) then
    HitPile := P_TAB + col;
end;

{ Which card index in a fanned tableau pile is under y? -1 = none. The last card
  gets its full height; earlier cards only their exposed fan strip. }
function THandler.HitCard(p, x, y: Integer): Integer;
var i, n, top, bot: Integer;
begin
  HitCard := -1;
  n := PileCount(p);
  for i := n - 1 downto 0 do
  begin
    top := CardTop(p, i);
    if i = n - 1 then bot := top + cardH else bot := CardTop(p, i + 1);
    if (y >= top) and (y < bot) then begin HitCard := i; Exit; end;
  end;
end;

{ Press: stock draws; otherwise pick up a card + the run stacked on it. }
procedure THandler.DoMouseDown(Sender: TControl; Button, X, Y: Integer);
var p, i: Integer;
begin
  p := HitPile(X, Y);
  if p < 0 then begin selPile := -1; Refresh; Exit; end;
  if p = P_STOCK then
  begin
    DrawStock;
    selPile := -1;
    Refresh;
    Exit;
  end;
  if p >= P_TAB then
  begin
    i := HitCard(p, X, Y);
    if (i < 0) or (not CardFaceUp(p, i)) then begin selPile := -1; Refresh; Exit; end;
    selPile := p; selStart := i;
  end
  else
  begin
    { waste / foundation: only the top card is grabbable }
    if PileCount(p) = 0 then begin selPile := -1; Refresh; Exit; end;
    selPile := p; selStart := PileCount(p) - 1;
  end;
  Refresh;
end;

{ Release: drop the grabbed run onto the pile under the cursor. Illegal -> no-op. }
procedure THandler.DoMouseUp(Sender: TControl; Button, X, Y: Integer);
var d, count: Integer;
begin
  if selPile < 0 then Exit;
  d := HitPile(X, Y);
  if (d >= 0) and (d <> selPile) then
  begin
    count := PileCount(selPile) - selStart;
    if TryMove(selPile, d, count) then moveCount := moveCount + 1;
  end;
  selPile := -1;
  Refresh;
end;

procedure THandler.DoKeyDown(Sender: TControl; KeyCode: Integer);
begin
  case KeyCode of
    110: DoNew(nil);        { n }
    117: DoUndo(nil);       { u }
    97:  DoAuto(nil);       { a }
    100: DoDraw(nil);       { d }
    32:  DoDraw(nil);       { space }
    113: gtk_main_quit;     { q }
  end;
end;

{ The paintbox was resized (by OnFormResize) — recompute the board for its size. }
procedure THandler.DoResize(Sender: TControl; Width, Height: Integer);
begin
  RecalcLayout(Width, Height);
  Refresh;
end;

{ The window was resized — stretch the paintbox to fill the content area; its own
  OnResize (DoResize) then recomputes the layout. }
procedure THandler.OnFormResize(Sender: TControl; Width, Height: Integer);
begin
  if PaintBox <> nil then PaintBox.SetBounds(0, 0, Width, Height);
end;

procedure THandler.DoNew(Sender: TObject);  begin NewGame(Random(100000) + 1); selPile := -1; moveCount := 0; Refresh; end;
procedure THandler.DoDraw(Sender: TObject); begin DrawStock; selPile := -1; Refresh; end;
procedure THandler.DoUndo(Sender: TObject); begin Undo; selPile := -1; Refresh; end;
procedure THandler.DoQuit(Sender: TObject); begin gtk_main_quit; end;
procedure THandler.DoHelp(Sender: TObject);
begin
  if Form <> nil then
    Form.Caption := 'Drag a card (with the run on it) to move; click the stock to draw';
end;
procedure THandler.DoAuto(Sender: TObject);
var moved: Boolean; p: Integer;
begin
  repeat
    moved := False;
    if AutoFoundation(P_WASTE) then begin moved := True; moveCount := moveCount + 1; end;
    for p := 0 to 6 do
      if AutoFoundation(P_TAB + p) then begin moved := True; moveCount := moveCount + 1; end;
  until not moved;
  selPile := -1; Refresh;
end;

function MkItem(const cap: string; parent: TMenuItem; m: TMethod): TMenuItem;
var it: TMenuItem;
begin
  it := TMenuItem.Create(nil);
  it.Caption := cap;
  it.OnClick := m;
  parent.Add(it);
  MkItem := it;
end;

{ --gui-smoke: self-quit once the real event loop is running. }
function GuiAutoQuit(data: Pointer): Integer; cdecl;
begin
  gtk_main_quit;
  GuiAutoQuit := 0;
end;

var
  Form1: TForm;
  PaintBox: TPaintBox;
  H: THandler;
  MainMenu: TMainMenu;
  GameMenu, HelpMenu: TMenuItem;
  pm: TMethod;
  arg: string;
begin
  Application := TApplication.Create;
  Application.Initialize;

  Form1 := TForm.Create(nil);
  Form1.Caption := 'Klondike';
  Form1.SetBounds(0, 0, 820, 640);

  PaintBox := TPaintBox.Create(nil);
  PaintBox.Parent := Form1;
  PaintBox.SetBounds(0, 0, 820, 610);

  H := THandler.Create(PaintBox, Form1);

  { menu bar — replaces the old right-hand button strip }
  MainMenu := TMainMenu.Create(nil);
  Form1.Menu := MainMenu;

  GameMenu := TMenuItem.Create(nil); GameMenu.Caption := '&Game'; MainMenu.Items.Add(GameMenu);
  pm.Data := H;
  pm.Code := @H.DoNew;  MkItem('&New',        GameMenu, pm);
  pm.Code := @H.DoDraw; MkItem('&Draw',       GameMenu, pm);
  pm.Code := @H.DoUndo; MkItem('&Undo',       GameMenu, pm);
  pm.Code := @H.DoAuto; MkItem('&Auto-play',  GameMenu, pm);
  pm.Code := @H.DoQuit; MkItem('&Quit',       GameMenu, pm);

  HelpMenu := TMenuItem.Create(nil); HelpMenu.Caption := '&Help'; MainMenu.Items.Add(HelpMenu);
  pm.Code := @H.DoHelp; MkItem('How to play',  HelpMenu, pm);

  { paint / input / resize wiring }
  pm.Code := @H.OnPaint;     pm.Data := H; PaintBox.OnPaint := pm;
  pm.Code := @H.DoMouseDown; pm.Data := H; PaintBox.OnMouseDown := pm;
  pm.Code := @H.DoMouseUp;   pm.Data := H; PaintBox.OnMouseUp := pm;
  pm.Code := @H.DoKeyDown;   pm.Data := H; PaintBox.OnKeyDown := pm;
  pm.Code := @H.DoResize;    pm.Data := H; PaintBox.OnResize := pm;
  pm.Code := @H.OnFormResize;pm.Data := H; Form1.OnResize := pm;

  Form1.Realize;
  Application.MainForm := Form1;
  H.Refresh;

  arg := '';
  if ParamCount > 0 then arg := ParamStr(1);
  if arg = '--smoke' then
  begin
    H.OnPaint(PaintBox, PaintBox.Canvas);
    H.DoMouseDown(PaintBox, 1, H.PileX(P_STOCK) + 5, H.PileY(P_STOCK) + 5);  { draw }
    if PileCount(P_WASTE) <> 1 then
    begin
      writeln('SMOKE FAIL: stock press did not draw');
      Halt(1);
    end;
    H.DoAuto(nil);
    H.DoResize(PaintBox, 1000, 760);
    if H.cardW <= 60 then
    begin
      writeln('SMOKE FAIL: resize did not enlarge cards');
      Halt(1);
    end;
    H.OnPaint(PaintBox, PaintBox.Canvas);
    writeln('SMOKE OK');
  end
  else if arg = '--gui-smoke' then
  begin
    g_timeout_add(400, @GuiAutoQuit, nil);
    Application.Run;
    writeln('GUI SMOKE OK');
  end
  else
    Application.Run;
end.
