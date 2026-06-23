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

type
  TDesigner = class
  public
    Doc: TDocModel;
    constructor Create;
    procedure Paint(Sender: TControl; Canvas: TCanvas);
  end;

implementation

uses sysutils;

constructor TDesigner.Create;
begin
  Doc := nil;
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
end;

end.
