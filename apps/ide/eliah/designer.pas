unit designer;

{ Eliah designer view — paints the garin docmodel as plain emulated boxes onto a
  TPaintBox canvas. NO live widgets: each node is a rectangle + caption + size
  hint. The docmodel is the truth; this is just one rendering of it. (ilja will
  render the same model with ANSI boxes.) }

interface

uses controls, graphics, docmodel;

const
  { Render palette (BGR). These belong in the implementation section, but a
    `const` block there before the constructor body trips
    bug-const-section-before-constructor — moved here temporarily, revert when
    that lands. Raw hex (not cl* names) sidesteps any const-init resolution. }
  COL_BG   = $00FAFAFA;   { surface background }
  COL_BOX  = $00E0E0E0;   { widget box fill }
  COL_EDGE = $00000000;   { widget outline (black) }
  COL_TEXT = $00000000;   { caption (black) }
  COL_DIM  = $00909090;   { size hint }
  COL_SEL  = $00FF6020;   { selection outline (orange, BGR) }
  COL_TRAY = $00C8E6FF;   { non-visual tray icon fill (pale amber, BGR) }
  HANDLE_HS = 4;          { corner-handle half-size for grab hit-testing }
  MIN_SIZE  = 8;          { smallest node a resize may produce }
  TRAY_ICW  = 78;         { tray icon width }
  TRAY_ICH  = 40;         { tray icon height }
  TRAY_PAD  = 8;          { gap from the form edges }
  TRAY_GAP  = 8;          { gap between tray icons }

type
  { corner under the cursor: 0 none, 1 TL, 2 TR, 3 BL, 4 BR }
  TDesigner = class
  public
    Doc: TDocModel;
    Sel: Integer;          { selected node index, -1 = none }
    Dragging: Boolean;     { a move-drag is in progress }
    DragDX, DragDY: Integer; { click offset inside the node being dragged }
    Resizing: Boolean;     { a corner-resize is in progress }
    ResizeCorner: Integer; { 1=TL 2=TR 3=BL 4=BR while resizing }
    constructor Create;
    procedure Paint(Sender: TControl; Canvas: TCanvas);
    { Position every non-visual node into a left-to-right strip along the bottom
      of the root form, writing the slot rect back into the node so the shared
      HitTest/selection machinery treats a tray icon like any other box. Derived
      geometry — safe to recompute every paint. }
    procedure LayoutTray;
    { hit-test the docmodel at (X, Y) and select the topmost node there
      (or clear selection). Returns the new selection index. }
    function SelectAt(X, Y: Integer): Integer;
    { which corner handle of node I covers (X, Y): 0 none, 1 TL,2 TR,3 BL,4 BR. }
    function HandleAt(I, X, Y: Integer): Integer;
    { mouse-press: if it lands on a handle of the current selection, start a
      resize; otherwise select the node under (X, Y) and start a move.
      Returns the selected index. }
    function BeginDrag(X, Y: Integer): Integer;
    { while a move or resize is in progress, track the cursor to (X, Y). }
    procedure DragTo(X, Y: Integer);
    procedure EndDrag;
  end;

implementation

uses sysutils;

constructor TDesigner.Create;
begin
  Doc := nil;
  Sel := -1;
  Dragging := False;
  DragDX := 0;
  DragDY := 0;
  Resizing := False;
  ResizeCorner := 0;
end;

function TDesigner.SelectAt(X, Y: Integer): Integer;
begin
  if Doc = nil then Sel := -1
  else Sel := Doc.HitTest(X, Y);
  Result := Sel;
end;

function Near(A, B: Integer): Boolean;
begin
  Near := (A >= B - HANDLE_HS) and (A <= B + HANDLE_HS);
end;

function TDesigner.HandleAt(I, X, Y: Integer): Integer;
var x0, y0, x1, y1: Integer;
begin
  Result := 0;
  if (Doc = nil) or (I < 0) or (I >= Doc.Count) then Exit;
  { tray icons are fixed — no resize handles }
  if Doc.IsNonVisual(Doc.NodeKind(I)) then Exit;
  x0 := Doc.NodeX(I);          y0 := Doc.NodeY(I);
  x1 := x0 + Doc.NodeW(I);     y1 := y0 + Doc.NodeH(I);
  if Near(X, x0) and Near(Y, y0) then Result := 1
  else if Near(X, x1) and Near(Y, y0) then Result := 2
  else if Near(X, x0) and Near(Y, y1) then Result := 3
  else if Near(X, x1) and Near(Y, y1) then Result := 4;
end;

function TDesigner.BeginDrag(X, Y: Integer): Integer;
var c: Integer;
begin
  Dragging := False;
  Resizing := False;
  { a press on a handle of the already-selected node starts a resize and keeps
    the selection (handles only show on the selected node). }
  if Sel >= 0 then
  begin
    c := HandleAt(Sel, X, Y);
    if c > 0 then
    begin
      Resizing := True;
      ResizeCorner := c;
      Result := Sel;
      Exit;
    end;
  end;
  { otherwise (re)select what's under the cursor and start a move. tray icons are
    fixed-position: select but never drag. }
  Result := SelectAt(X, Y);
  if (Result >= 0) and not Doc.IsNonVisual(Doc.NodeKind(Result)) then
  begin
    Dragging := True;
    DragDX := X - Doc.NodeX(Result);
    DragDY := Y - Doc.NodeY(Result);
  end;
end;

procedure TDesigner.DragTo(X, Y: Integer);
var x0, y0, x1, y1: Integer;
begin
  if (Doc = nil) or (Sel < 0) then Exit;

  if Dragging then
  begin
    Doc.SetNodeBounds(Sel, X - DragDX, Y - DragDY,
      Doc.NodeW(Sel), Doc.NodeH(Sel));
    Exit;
  end;

  if Resizing then
  begin
    { current corners; move only the dragged corner, clamp to MIN_SIZE }
    x0 := Doc.NodeX(Sel);        y0 := Doc.NodeY(Sel);
    x1 := x0 + Doc.NodeW(Sel);   y1 := y0 + Doc.NodeH(Sel);
    case ResizeCorner of
      1: begin x0 := X; y0 := Y; end;   { TL }
      2: begin x1 := X; y0 := Y; end;   { TR }
      3: begin x0 := X; y1 := Y; end;   { BL }
      4: begin x1 := X; y1 := Y; end;   { BR }
    end;
    if x1 - x0 < MIN_SIZE then
      if (ResizeCorner = 1) or (ResizeCorner = 3) then x0 := x1 - MIN_SIZE
      else x1 := x0 + MIN_SIZE;
    if y1 - y0 < MIN_SIZE then
      if (ResizeCorner = 1) or (ResizeCorner = 2) then y0 := y1 - MIN_SIZE
      else y1 := y0 + MIN_SIZE;
    Doc.SetNodeBounds(Sel, x0, y0, x1 - x0, y1 - y0);
  end;
end;

procedure TDesigner.EndDrag;
begin
  Dragging := False;
  Resizing := False;
end;

procedure TDesigner.LayoutTray;
var i, fi, fx, fy, fw, fh, slot, ty: Integer;
begin
  if Doc = nil then Exit;
  { the root form supplies the tray's frame }
  fi := -1;
  for i := 0 to Doc.Count - 1 do
    if (Doc.NodeParent(i) < 0) and (Doc.NodeKind(i) = wkForm) then
    begin fi := i; Break; end;
  if fi < 0 then Exit;
  fx := Doc.NodeX(fi);  fy := Doc.NodeY(fi);
  fw := Doc.NodeW(fi);  fh := Doc.NodeH(fi);
  ty := fy + fh - TRAY_PAD - TRAY_ICH;
  slot := 0;
  for i := 0 to Doc.Count - 1 do
    if Doc.IsNonVisual(Doc.NodeKind(i)) then
    begin
      Doc.SetNodeBounds(i,
        fx + TRAY_PAD + slot * (TRAY_ICW + TRAY_GAP), ty, TRAY_ICW, TRAY_ICH);
      Inc(slot);
    end;
end;

procedure TDesigner.Paint(Sender: TControl; Canvas: TCanvas);
var
  i, x, y, w, h: Integer;
  nonvis: Boolean;
begin
  { clear the surface }
  Canvas.Brush.Color := COL_BG;
  Canvas.Pen.Color := COL_BG;
  Canvas.Rectangle(0, 0, 4000, 4000);

  if Doc = nil then Exit;
  LayoutTray;   { refresh tray slot rects before drawing/hit-testing }

  for i := 0 to Doc.Count - 1 do
  begin
    nonvis := Doc.IsNonVisual(Doc.NodeKind(i));
    x := Doc.NodeX(i);
    y := Doc.NodeY(i);
    w := Doc.NodeW(i);
    h := Doc.NodeH(i);

    if Doc.NodeKind(i) = wkForm then
      Canvas.Brush.Color := COL_BG
    else if nonvis then
      Canvas.Brush.Color := COL_TRAY
    else
      Canvas.Brush.Color := COL_BOX;
    Canvas.Pen.Color := COL_EDGE;
    Canvas.Pen.Width := 1;
    Canvas.Rectangle(x, y, x + w, y + h);

    Canvas.Font.Name := 'Sans';
    Canvas.Font.Size := 9;
    Canvas.Font.Color := COL_TEXT;
    Canvas.TextOut(x + 4, y + 3,
      Doc.KindName(Doc.NodeKind(i)) + ': ' + Doc.NodeCaption(i));

    { size hint only for positioned widgets; tray icons have no meaningful size }
    if not nonvis then
    begin
      Canvas.Font.Color := COL_DIM;
      Canvas.TextOut(x + 4, y + h - 16, IntToStr(w) + 'x' + IntToStr(h));
    end;
  end;

  { selection outline + corner handles, painted over the boxes }
  if (Doc <> nil) and (Sel >= 0) and (Sel < Doc.Count) then
  begin
    x := Doc.NodeX(Sel);
    y := Doc.NodeY(Sel);
    w := Doc.NodeW(Sel);
    h := Doc.NodeH(Sel);

    Canvas.Brush.Color := COL_BG;
    Canvas.Pen.Color := COL_SEL;
    Canvas.Pen.Width := 2;
    Canvas.Rectangle(x - 1, y - 1, x + w + 1, y + h + 1);

    { 4 solid corner handles — only on resizable (visual) nodes }
    if not Doc.IsNonVisual(Doc.NodeKind(Sel)) then
    begin
      Canvas.Brush.Color := COL_SEL;
      Canvas.Pen.Color := COL_SEL;
      Canvas.Pen.Width := 1;
      Canvas.Rectangle(x - 3,     y - 3,     x + 3,     y + 3);
      Canvas.Rectangle(x + w - 3, y - 3,     x + w + 3, y + 3);
      Canvas.Rectangle(x - 3,     y + h - 3, x + 3,     y + h + 3);
      Canvas.Rectangle(x + w - 3, y + h - 3, x + w + 3, y + h + 3);
    end;
  end;
end;

end.
