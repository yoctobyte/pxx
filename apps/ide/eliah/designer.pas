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

type
  TDesigner = class
  public
    Doc: TDocModel;
    Sel: Integer;          { selected node index, -1 = none }
    constructor Create;
    procedure Paint(Sender: TControl; Canvas: TCanvas);
    { hit-test the docmodel at (X, Y) and select the topmost node there
      (or clear selection). Returns the new selection index. }
    function SelectAt(X, Y: Integer): Integer;
  end;

implementation

uses sysutils;

constructor TDesigner.Create;
begin
  Doc := nil;
  Sel := -1;
end;

function TDesigner.SelectAt(X, Y: Integer): Integer;
begin
  if Doc = nil then Sel := -1
  else Sel := Doc.HitTest(X, Y);
  Result := Sel;
end;

procedure TDesigner.Paint(Sender: TControl; Canvas: TCanvas);
var
  i, x, y, w, h: Integer;
begin
  { clear the surface }
  Canvas.Brush.Color := COL_BG;
  Canvas.Pen.Color := COL_BG;
  Canvas.Rectangle(0, 0, 4000, 4000);

  if Doc = nil then Exit;

  for i := 0 to Doc.Count - 1 do
  begin
    x := Doc.NodeX(i);
    y := Doc.NodeY(i);
    w := Doc.NodeW(i);
    h := Doc.NodeH(i);

    if Doc.NodeKind(i) = wkForm then
      Canvas.Brush.Color := COL_BG
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

    Canvas.Font.Color := COL_DIM;
    Canvas.TextOut(x + 4, y + h - 16, IntToStr(w) + 'x' + IntToStr(h));
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

    { 4 solid corner handles }
    Canvas.Brush.Color := COL_SEL;
    Canvas.Pen.Color := COL_SEL;
    Canvas.Pen.Width := 1;
    Canvas.Rectangle(x - 3,     y - 3,     x + 3,     y + 3);
    Canvas.Rectangle(x + w - 3, y - 3,     x + w + 3, y + 3);
    Canvas.Rectangle(x - 3,     y + h - 3, x + 3,     y + h + 3);
    Canvas.Rectangle(x + w - 3, y + h - 3, x + w + 3, y + h + 3);
  end;
end;

end.
