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
    selected: Integer;
    PaintBox: TPaintBox;
    StatusLabel: TLabel;
    constructor Create(APaint: TPaintBox; ALabel: TLabel);
    procedure DrawCard(Canvas: TCanvas; x, y, suit, rank: Integer; faceUp: Boolean);
    procedure DrawPile(Canvas: TCanvas; p, x, y: Integer; fanned: Boolean);
    procedure OnPaint(Sender: TControl; Canvas: TCanvas);
    procedure Refresh;
    procedure SelectPile(p: Integer);
    function FaceUpRun(p: Integer): Integer;
    procedure DoNew(Sender: TObject);
    procedure DoDraw(Sender: TObject);
    procedure DoUndo(Sender: TObject);
    procedure DoAuto(Sender: TObject);
    procedure DoFound(Sender: TObject);
    procedure DoSelW(Sender: TObject);
    procedure DoSel1(Sender: TObject);
    procedure DoSel2(Sender: TObject);
    procedure DoSel3(Sender: TObject);
    procedure DoSel4(Sender: TObject);
    procedure DoSel5(Sender: TObject);
    procedure DoSel6(Sender: TObject);
    procedure DoSel7(Sender: TObject);
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
    if IsWon then StatusLabel.Caption := 'You win!'
    else if selected >= 0 then StatusLabel.Caption := 'Source selected'
    else StatusLabel.Caption := 'Pick a pile';
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

procedure THandler.SelectPile(p: Integer);
var k: Integer; done: Boolean;
begin
  if selected < 0 then
    selected := p
  else
  begin
    { move the largest legal face-up run from `selected` onto p }
    done := False;
    k := FaceUpRun(selected);
    while (k >= 1) and (not done) do
    begin
      if TryMove(selected, p, k) then done := True;
      k := k - 1;
    end;
    selected := -1;
  end;
  Refresh;
end;

procedure THandler.DoNew(Sender: TObject);  begin NewGame(Random(100000) + 1); selected := -1; Refresh; end;
procedure THandler.DoDraw(Sender: TObject); begin DrawStock; selected := -1; Refresh; end;
procedure THandler.DoUndo(Sender: TObject); begin Undo; selected := -1; Refresh; end;
procedure THandler.DoFound(Sender: TObject);
begin
  if selected >= 0 then AutoFoundation(selected);
  selected := -1; Refresh;
end;
procedure THandler.DoAuto(Sender: TObject);
var moved: Boolean; p: Integer;
begin
  repeat
    moved := False;
    if AutoFoundation(P_WASTE) then moved := True;
    for p := 0 to 6 do
      if AutoFoundation(P_TAB + p) then moved := True;
  until not moved;
  selected := -1; Refresh;
end;
procedure THandler.DoSelW(Sender: TObject); begin SelectPile(P_WASTE); end;
procedure THandler.DoSel1(Sender: TObject); begin SelectPile(P_TAB + 0); end;
procedure THandler.DoSel2(Sender: TObject); begin SelectPile(P_TAB + 1); end;
procedure THandler.DoSel3(Sender: TObject); begin SelectPile(P_TAB + 2); end;
procedure THandler.DoSel4(Sender: TObject); begin SelectPile(P_TAB + 3); end;
procedure THandler.DoSel5(Sender: TObject); begin SelectPile(P_TAB + 4); end;
procedure THandler.DoSel6(Sender: TObject); begin SelectPile(P_TAB + 5); end;
procedure THandler.DoSel7(Sender: TObject); begin SelectPile(P_TAB + 6); end;

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
  Status.Caption := 'Pick a pile';
  Status.SetBounds(580, 10, 200, 24);

  H := THandler.Create(PaintBox, Status);

  pm.Code := @H.OnPaint; pm.Data := H;
  PaintBox.OnPaint := pm;

  pm.Data := H;
  pm.Code := @H.DoNew;   MkButton(Form1, 'New',      580,  50, 90, pm);
  pm.Code := @H.DoDraw;  MkButton(Form1, 'Draw',     580,  84, 90, pm);
  pm.Code := @H.DoUndo;  MkButton(Form1, 'Undo',     580, 118, 90, pm);
  pm.Code := @H.DoFound; MkButton(Form1, 'To Found', 580, 152, 90, pm);
  pm.Code := @H.DoAuto;  MkButton(Form1, 'Auto',     580, 186, 90, pm);
  pm.Code := @H.DoSelW;  MkButton(Form1, 'Waste',    580, 240, 90, pm);
  pm.Code := @H.DoSel1;  MkButton(Form1, 'T1', 580, 274, 42, pm);
  pm.Code := @H.DoSel2;  MkButton(Form1, 'T2', 626, 274, 42, pm);
  pm.Code := @H.DoSel3;  MkButton(Form1, 'T3', 580, 308, 42, pm);
  pm.Code := @H.DoSel4;  MkButton(Form1, 'T4', 626, 308, 42, pm);
  pm.Code := @H.DoSel5;  MkButton(Form1, 'T5', 580, 342, 42, pm);
  pm.Code := @H.DoSel6;  MkButton(Form1, 'T6', 626, 342, 42, pm);
  pm.Code := @H.DoSel7;  MkButton(Form1, 'T7', 580, 376, 42, pm);

  Form1.Realize;

  arg := '';
  if ParamCount > 0 then arg := ParamStr(1);
  if arg = '--smoke' then
  begin
    { headless integration check: render, run a few engine moves, render again. }
    H.OnPaint(PaintBox, PaintBox.Canvas);
    H.DoDraw(nil);
    H.DoAuto(nil);
    H.SelectPile(P_TAB + 6);
    H.SelectPile(P_TAB + 5);
    H.OnPaint(PaintBox, PaintBox.Canvas);
    writeln('SMOKE OK');
  end
  else
    Application.Run;
end.
