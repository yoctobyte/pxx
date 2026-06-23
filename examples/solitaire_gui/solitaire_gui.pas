program solitaire_gui;
{ Klondike solitaire — PCL/GTK3 GUI front-end over the tested `klondike` engine.
  The board is custom-drawn in a TPaintBox.OnPaint; play is button-driven because
  PCL currently exposes only OnClick (no mouse coordinates / drag) — click a pile
  button to select a source, then a destination (or 'To Found'); New / Draw /
  Undo / Auto act immediately. Each action repaints via Invalidate.

  `--smoke`: set up, render the board once, run a few engine moves, render again,
  print SMOKE OK and exit (no event loop) — a headless integration check that the
  whole stack draws without crashing. Without it, runs the interactive app. }

{$define PXX_MANAGED_STRING}

uses gtk3, controls, stdctrls, forms, extctrls, graphics, sysutils, klondike;

const
  CARD_W = 60; CARD_H = 84;
  FAN_UP = 22; FAN_DOWN = 8;
  COL_TABLE = $00104010;   { dark green, $00BBGGRR }
  COL_BACK  = $00803020;   { card back }
  COL_EMPTY = $00405040;
  COL_GRAY  = $00808080;

type
  THandler = class
    selected: Integer;     { the pile being dragged from, -1 = none }
    moveCount: Integer;
    PaintBox: TPaintBox;
    StatusLabel: TLabel;
    constructor Create(APaint: TPaintBox; ALabel: TLabel);
    procedure DrawCard(Canvas: TCanvas; x, y, suit, rank: Integer; faceUp: Boolean);
    procedure DrawPile(Canvas: TCanvas; p, x, y: Integer; fanned: Boolean);
    procedure OnPaint(Sender: TControl; Canvas: TCanvas);
    procedure Refresh;
    function FaceUpRun(p: Integer): Integer;
    function HitPile(x, y: Integer): Integer;
    function DoMoveBest(src, dst: Integer): Boolean;
    procedure DoMouseDown(Sender: TControl; Button, X, Y: Integer);
    procedure DoMouseUp(Sender: TControl; Button, X, Y: Integer);
    procedure DoKeyDown(Sender: TControl; KeyCode: Integer);
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
  NewGame(1);
end;

procedure THandler.DrawCard(Canvas: TCanvas; x, y, suit, rank: Integer; faceUp: Boolean);
begin
  Canvas.Pen.Color := clBlack;
  Canvas.Pen.Width := 1;
  if faceUp then
  begin
    Canvas.Brush.Color := clWhite;
    Canvas.Rectangle(x, y, x + CARD_W, y + CARD_H);
    if IsRed(suit) then Canvas.Font.Color := clRed else Canvas.Font.Color := clBlack;
    Canvas.Font.Name := 'Sans';
    Canvas.Font.Size := 12;
    Canvas.TextOut(x + 4, y + 3, RankStr(rank) + SuitStr(suit));
  end
  else
  begin
    Canvas.Brush.Color := COL_BACK;
    Canvas.Rectangle(x, y, x + CARD_W, y + CARD_H);
  end;
end;

procedure THandler.DrawPile(Canvas: TCanvas; p, x, y: Integer; fanned: Boolean);
var i, n, cy, dy: Integer;
begin
  n := PileCount(p);
  if n = 0 then
  begin
    Canvas.Brush.Color := COL_EMPTY;
    Canvas.Pen.Color := COL_GRAY;
    Canvas.Rectangle(x, y, x + CARD_W, y + CARD_H);
    Exit;
  end;
  if not fanned then
  begin
    { only the top card visible (stock/waste/foundations) }
    DrawCard(Canvas, x, y, CardSuit(p, n - 1), CardRank(p, n - 1), CardFaceUp(p, n - 1));
    Exit;
  end;
  cy := y;
  for i := 0 to n - 1 do
  begin
    DrawCard(Canvas, x, cy, CardSuit(p, i), CardRank(p, i), CardFaceUp(p, i));
    if CardFaceUp(p, i) then dy := FAN_UP else dy := FAN_DOWN;
    cy := cy + dy;
  end;
end;

procedure THandler.OnPaint(Sender: TControl; Canvas: TCanvas);
var c: Integer;
begin
  if Canvas = nil then Exit;
  Canvas.Brush.Color := COL_TABLE;
  Canvas.Pen.Color := COL_TABLE;
  Canvas.Rectangle(0, 0, 700, 560);

  DrawPile(Canvas, P_STOCK, 10, 10, False);
  DrawPile(Canvas, P_WASTE, 80, 10, False);
  for c := 0 to 3 do DrawPile(Canvas, P_FOUND + c, 290 + c * 70, 10, False);
  for c := 0 to 6 do DrawPile(Canvas, P_TAB + c, 10 + c * 70, 110, True);

  { highlight the selected pile's column }
  if selected >= 0 then
  begin
    Canvas.Brush.Color := clNone;
    Canvas.Pen.Color := clYellow;
    Canvas.Pen.Width := 3;
    if selected = P_WASTE then Canvas.Rectangle(79, 9, 81 + CARD_W, 11 + CARD_H)
    else if (selected >= P_TAB) then
      Canvas.Rectangle(9 + (selected - P_TAB) * 70, 109, 11 + (selected - P_TAB) * 70 + CARD_W, 540);
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

{ Which pile is at (x,y)? Mirrors the OnPaint layout. -1 = none. }
function THandler.HitPile(x, y: Integer): Integer;
var c: Integer;
begin
  HitPile := -1;
  if (y >= 10) and (y < 10 + CARD_H) then
  begin
    if (x >= 10) and (x < 10 + CARD_W) then HitPile := P_STOCK
    else if (x >= 80) and (x < 80 + CARD_W) then HitPile := P_WASTE
    else
    begin
      c := (x - 290) div 70;
      if (c >= 0) and (c < 4) and (x >= 290 + c * 70) and (x < 290 + c * 70 + CARD_W) then
        HitPile := P_FOUND + c;
    end;
  end
  else if y >= 110 then
  begin
    c := (x - 10) div 70;
    if (c >= 0) and (c < 7) and (x >= 10 + c * 70) and (x < 10 + c * 70 + CARD_W) then
      HitPile := P_TAB + c;
  end;
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
  b := TButton.Create;
  b.Parent := Form;
  b.Caption := cap;
  b.SetBounds(x, y, w, 28);
  b.OnClick := m;
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

  Form1 := TForm.Create;
  Form1.Caption := 'Klondike Solitaire';

  PaintBox := TPaintBox.Create;
  PaintBox.Parent := Form1;
  PaintBox.SetBounds(0, 0, 560, 560);

  Status := TLabel.Create;
  Status.Parent := Form1;
  Status.Caption := 'Moves: 0   (drag cards; keys: n/u/a/d/q)';
  Status.SetBounds(580, 10, 220, 24);

  H := THandler.Create(PaintBox, Status);

  pm.Code := @H.OnPaint; pm.Data := H;
  PaintBox.OnPaint := pm;
  pm.Code := @H.DoMouseDown; pm.Data := H;
  PaintBox.OnMouseDown := pm;     { press a pile to start a drag }
  pm.Code := @H.DoMouseUp; pm.Data := H;
  PaintBox.OnMouseUp := pm;       { release on a pile to drop }
  pm.Code := @H.DoKeyDown; pm.Data := H;
  PaintBox.OnKeyDown := pm;       { n/u/a/d/q shortcuts }

  pm.Data := H;
  pm.Code := @H.DoNew;   MkButton(Form1, 'New',  580,  50, 90, pm);
  pm.Code := @H.DoUndo;  MkButton(Form1, 'Undo', 580,  84, 90, pm);
  pm.Code := @H.DoAuto;  MkButton(Form1, 'Auto', 580, 118, 90, pm);

  Form1.Realize;

  arg := '';
  if ParamCount > 0 then arg := ParamStr(1);
  if arg = '--smoke' then
  begin
    { headless integration check through the drag handlers: press the stock to
      draw (asserts hit-test -> action), auto to foundations, then a drag
      (press col 6, release col 5) exercises the click-to-move path. A key
      shortcut (u = undo) exercises the keyboard path. }
    H.OnPaint(PaintBox, PaintBox.Canvas);
    H.DoMouseDown(PaintBox, 1, 30, 40);          { stock -> draw }
    if PileCount(P_WASTE) <> 1 then
    begin
      writeln('SMOKE FAIL: stock click did not draw');
      Halt(1);
    end;
    H.DoAuto(nil);
    H.DoMouseDown(PaintBox, 1, 10 + 6 * 70 + 5, 200);  { press tableau col 6 }
    H.DoMouseUp(PaintBox, 1, 10 + 5 * 70 + 5, 200);    { release on col 5 }
    H.DoKeyDown(PaintBox, 117);                          { 'u' = undo }
    H.OnPaint(PaintBox, PaintBox.Canvas);
    writeln('SMOKE OK');
  end
  else
    Application.Run;
end.
