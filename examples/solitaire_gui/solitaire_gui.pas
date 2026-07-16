{ SPDX-License-Identifier: 0BSD }
program solitaire_gui;
{ Klondike solitaire — PCL/GTK3 GUI front-end over the tested `klondike` engine.
  The board is custom-drawn in TPaintBox.OnPaint and played by dragging cards:
  press a pile (OnMouseDown) to pick up its top run, release on a destination
  (OnMouseUp) to drop; press the stock to draw. Keyboard (OnKeyDown): n=new,
  u=undo, a=auto, d/space=draw, q=quit. The layout (card size, pile spacing,
  hit-test regions) is recomputed on resize (OnResize), so the board scales with
  the window. New / Undo / Auto buttons and a move counter complete it.

  `--smoke`: set up, drive the handlers headlessly (draw, drag, key, resize),
  assert a stock press draws, print SMOKE OK and exit (no event loop).

  `--gui-smoke`: map the REAL window and run the REAL event loop (gtk_main via
  Application.Run), self-quitting from a g_timeout so the realize/map/paint/
  teardown path is exercised (under xvfb in CI); prints GUI SMOKE OK. }

{$define PXX_MANAGED_STRING}

uses gtk3, controls, stdctrls, forms, extctrls, graphics, sysutils, klondike;

const
  COL_TABLE = $00104010;   { dark green, $00BBGGRR }
  COL_BACK  = $00803020;   { card back }
  COL_EMPTY = $00405040;
  COL_GRAY  = $00808080;

type
  THandler = class
    selected: Integer;     { the pile being dragged from, -1 = none }
    moveCount: Integer;
    { responsive layout, recomputed on resize }
    boardW, boardH, cardW, cardH, colStep, marginX, topY, tabY, fanUp, fanDown: Integer;
    PaintBox: TPaintBox;
    StatusLabel: TLabel;
    constructor Create(APaint: TPaintBox; ALabel: TLabel);
    procedure RecalcLayout(w, h: Integer);
    function PileX(p: Integer): Integer;
    function PileY(p: Integer): Integer;
    procedure DrawCard(Canvas: TCanvas; x, y, suit, rank: Integer; faceUp: Boolean);
    procedure DrawPile(Canvas: TCanvas; p: Integer; fanned: Boolean);
    procedure OnPaint(Sender: TControl; Canvas: TCanvas);
    procedure Refresh;
    function FaceUpRun(p: Integer): Integer;
    function HitPile(x, y: Integer): Integer;
    function DoMoveBest(src, dst: Integer): Boolean;
    procedure DoMouseDown(Sender: TControl; Button, X, Y: Integer);
    procedure DoMouseUp(Sender: TControl; Button, X, Y: Integer);
    procedure DoKeyDown(Sender: TControl; KeyCode: Integer);
    procedure DoResize(Sender: TControl; Width, Height: Integer);
    procedure DoNew(Sender: TObject);
    procedure DoDraw(Sender: TObject);
    procedure DoUndo(Sender: TObject);
    procedure DoAuto(Sender: TObject);
  end;

function RankStr(r: Integer): string;
begin
  if r = 1 then RankStr := 'A'
  else if r = 10 then RankStr := 'T'
  else if r = 11 then RankStr := 'J'
  else if r = 12 then RankStr := 'Q'
  else if r = 13 then RankStr := 'K'
  else RankStr := IntToStr(r);
end;

function SuitStr(s: Integer): string;
begin
  if s = 0 then SuitStr := 'C'
  else if s = 1 then SuitStr := 'D'
  else if s = 2 then SuitStr := 'H'
  else SuitStr := 'S';
end;

constructor THandler.Create(APaint: TPaintBox; ALabel: TLabel);
begin
  PaintBox := APaint;
  StatusLabel := ALabel;
  selected := -1;
  moveCount := 0;
  RecalcLayout(560, 560);
  NewGame(1);
end;

{ Recompute card size / spacing / hit-test geometry for a w x h board. The 7
  tableau columns fill the width; everything else derives from the column step. }
procedure THandler.RecalcLayout(w, h: Integer);
begin
  if w < 360 then w := 360;
  if h < 360 then h := 360;
  boardW := w; boardH := h;
  colStep := w div 7;
  cardW := colStep - 8;
  if cardW < 36 then cardW := 36;
  cardH := cardW * 7 div 5;
  marginX := (w - colStep * 7) div 2;
  topY := 10;
  tabY := topY + cardH + 16;
  fanUp := cardH div 4;   if fanUp < 10 then fanUp := 10;
  fanDown := cardH div 12; if fanDown < 3 then fanDown := 3;
end;

{ column index of each pile in the grid: stock 0, waste 1, foundations 3..6,
  tableau 0..6 (foundations share the top row, tableau the lower one). }
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

procedure THandler.DrawCard(Canvas: TCanvas; x, y, suit, rank: Integer; faceUp: Boolean);
var fs: Integer;
begin
  Canvas.Pen.Color := clBlack;
  Canvas.Pen.Width := 1;
  if faceUp then
  begin
    Canvas.Brush.Color := clWhite;
    Canvas.Rectangle(x, y, x + cardW, y + cardH);
    if IsRed(suit) then Canvas.Font.Color := clRed else Canvas.Font.Color := clBlack;
    fs := cardH div 6; if fs < 8 then fs := 8;
    Canvas.Font.Name := 'Sans';
    Canvas.Font.Size := fs;
    Canvas.TextOut(x + 4, y + 3, RankStr(rank) + SuitStr(suit));
  end
  else
  begin
    Canvas.Brush.Color := COL_BACK;
    Canvas.Rectangle(x, y, x + cardW, y + cardH);
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
var c, x, y: Integer;
begin
  if Canvas = nil then Exit;
  Canvas.Brush.Color := COL_TABLE;
  Canvas.Pen.Color := COL_TABLE;
  Canvas.Rectangle(0, 0, boardW, boardH);

  DrawPile(Canvas, P_STOCK, False);
  DrawPile(Canvas, P_WASTE, False);
  for c := 0 to N_FOUND - 1 do DrawPile(Canvas, P_FOUND + c, False);
  for c := 0 to N_TAB - 1 do DrawPile(Canvas, P_TAB + c, True);

  if selected >= 0 then
  begin
    Canvas.Brush.Color := clNone;
    Canvas.Pen.Color := clYellow;
    Canvas.Pen.Width := 3;
    x := PileX(selected); y := PileY(selected);
    if selected >= P_TAB then
      Canvas.Rectangle(x - 1, y - 1, x + cardW + 1, boardH - 4)
    else
      Canvas.Rectangle(x - 1, y - 1, x + cardW + 1, y + cardH + 1);
  end;
end;

procedure THandler.Refresh;
begin
  if StatusLabel <> nil then
  begin
    if IsWon then StatusLabel.Caption := 'You win!  Moves: ' + IntToStr(moveCount)
    else StatusLabel.Caption := 'Moves: ' + IntToStr(moveCount);
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

{ Move the largest legal face-up run from src onto dst; counts on success. }
function THandler.DoMoveBest(src, dst: Integer): Boolean;
var k: Integer;
begin
  DoMoveBest := False;
  k := FaceUpRun(src);
  while (k >= 1) and (not DoMoveBest) do
  begin
    if TryMove(src, dst, k) then
    begin
      moveCount := moveCount + 1;
      DoMoveBest := True;
    end;
    k := k - 1;
  end;
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

{ Press: clicking the stock draws; otherwise begin a drag from that pile. }
procedure THandler.DoMouseDown(Sender: TControl; Button, X, Y: Integer);
var p: Integer;
begin
  p := HitPile(X, Y);
  if p < 0 then Exit;
  if p = P_STOCK then
  begin
    DrawStock;
    selected := -1;
  end
  else
    selected := p;
  Refresh;
end;

{ Release: drop the dragged run onto the pile under the cursor. }
procedure THandler.DoMouseUp(Sender: TControl; Button, X, Y: Integer);
var d: Integer; ok: Boolean;
begin
  if selected < 0 then Exit;
  d := HitPile(X, Y);
  if (d >= 0) and (d <> selected) then ok := DoMoveBest(selected, d);
  selected := -1;
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

procedure THandler.DoResize(Sender: TControl; Width, Height: Integer);
begin
  RecalcLayout(Width, Height);
  Refresh;
end;

procedure THandler.DoNew(Sender: TObject);  begin NewGame(Random(100000) + 1); selected := -1; moveCount := 0; Refresh; end;
procedure THandler.DoDraw(Sender: TObject); begin DrawStock; selected := -1; Refresh; end;
procedure THandler.DoUndo(Sender: TObject); begin Undo; selected := -1; Refresh; end;
procedure THandler.DoAuto(Sender: TObject);
var moved: Boolean; p: Integer;
begin
  repeat
    moved := False;
    if AutoFoundation(P_WASTE) then begin moved := True; moveCount := moveCount + 1; end;
    for p := 0 to 6 do
      if AutoFoundation(P_TAB + p) then begin moved := True; moveCount := moveCount + 1; end;
  until not moved;
  selected := -1; Refresh;
end;

procedure MkButton(Form: TForm; const cap: string; x, y, w: Integer; m: TMethod);
var b: TButton;
begin
  b := TButton.Create(nil);
  b.Parent := Form;
  b.Caption := cap;
  b.SetBounds(x, y, w, 28);
  b.OnClick := m;
end;

{ --gui-smoke: self-quit fired by g_timeout_add once the real event loop has
  been running (the window is mapped and painted by then). }
function GuiAutoQuit(data: Pointer): Integer; cdecl;
begin
  gtk_main_quit;
  GuiAutoQuit := 0;   { one-shot: remove the source }
end;

var
  Form1: TForm;
  PaintBox: TPaintBox;
  Status: TLabel;
  H: THandler;
  pm: TMethod;
  arg: string;

begin
  Application := TApplication.Create;
  Application.Initialize;

  Form1 := TForm.Create(nil);
  Form1.Caption := 'Klondike Solitaire';

  PaintBox := TPaintBox.Create(nil);
  PaintBox.Parent := Form1;
  PaintBox.SetBounds(0, 0, 560, 560);

  Status := TLabel.Create(nil);
  Status.Parent := Form1;
  Status.Caption := 'Moves: 0   (drag cards; keys: n/u/a/d/q)';
  Status.SetBounds(580, 10, 220, 24);

  H := THandler.Create(PaintBox, Status);

  pm.Code := @H.OnPaint;     pm.Data := H; PaintBox.OnPaint := pm;
  pm.Code := @H.DoMouseDown; pm.Data := H; PaintBox.OnMouseDown := pm;  { press to pick up }
  pm.Code := @H.DoMouseUp;   pm.Data := H; PaintBox.OnMouseUp := pm;    { release to drop }
  pm.Code := @H.DoKeyDown;   pm.Data := H; PaintBox.OnKeyDown := pm;    { n/u/a/d/q }
  pm.Code := @H.DoResize;    pm.Data := H; PaintBox.OnResize := pm;     { rescale board }

  pm.Data := H;
  pm.Code := @H.DoNew;   MkButton(Form1, 'New',  580,  50, 90, pm);
  pm.Code := @H.DoUndo;  MkButton(Form1, 'Undo', 580,  84, 90, pm);
  pm.Code := @H.DoAuto;  MkButton(Form1, 'Auto', 580, 118, 90, pm);

  Form1.Realize;
  { register as the application main form so Application.Run shows it — without
    this FMainForm stays nil and Run only spins the event loop, leaving the real
    toplevel created but never shown (only GTK's tiny helper window maps). }
  Application.MainForm := Form1;

  arg := '';
  if ParamCount > 0 then arg := ParamStr(1);
  if arg = '--smoke' then
  begin
    { headless integration check through the handlers: stock press must draw
      (asserts hit-test -> action), auto + a drag (press col6 / release col5),
      a key (u = undo), and a resize that must rescale the card geometry. }
    H.OnPaint(PaintBox, PaintBox.Canvas);
    H.DoMouseDown(PaintBox, 1, H.PileX(P_STOCK) + 5, H.PileY(P_STOCK) + 5);  { draw }
    if PileCount(P_WASTE) <> 1 then
    begin
      writeln('SMOKE FAIL: stock press did not draw');
      Halt(1);
    end;
    H.DoAuto(nil);
    H.DoMouseDown(PaintBox, 1, H.PileX(P_TAB + 6) + 5, H.tabY + 5);  { pick up col 6 }
    H.DoMouseUp(PaintBox, 1, H.PileX(P_TAB + 5) + 5, H.tabY + 5);    { drop on col 5 }
    H.DoKeyDown(PaintBox, 117);                                       { 'u' = undo }
    H.DoResize(PaintBox, 840, 700);
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
    { real-window smoke: run the actual event loop (window maps + paints on a
      live surface), self-quit after 400ms. The suite runs this under xvfb. }
    g_timeout_add(400, @GuiAutoQuit, nil);
    Application.Run;
    writeln('GUI SMOKE OK');
  end
  else
    Application.Run;
end.
