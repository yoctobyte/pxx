unit docmodel;

{ garin core — the designed-form document. Render-agnostic widget tree: the
  SOURCE OF TRUTH. It serializes to .lfm/.pas and is what every face renders
  (eliah paints boxes from it; ilja paints ANSI boxes from it). No GTK, no ANSI,
  no live widgets here.

  Node is deliberately minimal: width + height + parent cover ~9/10 design cases;
  caption matters for labels/buttons. Coords are px, relative to the design
  surface. }

interface

type
  TWidgetKind = (
    wkForm, wkPanel, wkButton, wkLabel, wkEdit,
    wkMemo, wkListBox, wkCheckBox);

  TDocNode = record
    Kind: TWidgetKind;
    Caption: AnsiString;
    Parent: Integer;   { index into the model; -1 = the form/root }
    X, Y, W, H: Integer;
  end;

  TDocModel = class
  private
    FNodes: array of TDocNode;
    FCount: Integer;
  public
    constructor Create;
    function AddNode(AKind: TWidgetKind; const ACaption: AnsiString;
      AParent, AX, AY, AW, AH: Integer): Integer;
    procedure SetNodeBounds(I, AX, AY, AW, AH: Integer);
    function Count: Integer;
    { topmost node whose rect contains (AX, AY), or -1 if none. Later-added
      nodes sit on top (children drawn after parents), so scan back-to-front. }
    function HitTest(AX, AY: Integer): Integer;
    { field accessors (avoid record-by-value return paths) }
    function NodeKind(I: Integer): TWidgetKind;
    function NodeCaption(I: Integer): AnsiString;
    function NodeParent(I: Integer): Integer;
    function NodeX(I: Integer): Integer;
    function NodeY(I: Integer): Integer;
    function NodeW(I: Integer): Integer;
    function NodeH(I: Integer): Integer;
    function KindName(K: TWidgetKind): AnsiString;
  end;

implementation

constructor TDocModel.Create;
begin
  FCount := 0;
  SetLength(FNodes, 0);
end;

function TDocModel.AddNode(AKind: TWidgetKind; const ACaption: AnsiString;
  AParent, AX, AY, AW, AH: Integer): Integer;
begin
  SetLength(FNodes, FCount + 1);
  FNodes[FCount].Kind := AKind;
  FNodes[FCount].Caption := ACaption;
  FNodes[FCount].Parent := AParent;
  FNodes[FCount].X := AX;
  FNodes[FCount].Y := AY;
  FNodes[FCount].W := AW;
  FNodes[FCount].H := AH;
  Result := FCount;
  Inc(FCount);
end;

procedure TDocModel.SetNodeBounds(I, AX, AY, AW, AH: Integer);
begin
  if (I < 0) or (I >= FCount) then Exit;
  FNodes[I].X := AX;
  FNodes[I].Y := AY;
  FNodes[I].W := AW;
  FNodes[I].H := AH;
end;

function TDocModel.Count: Integer;
begin
  Result := FCount;
end;

function TDocModel.HitTest(AX, AY: Integer): Integer;
var i: Integer;
begin
  Result := -1;
  for i := FCount - 1 downto 0 do
    if (AX >= FNodes[i].X) and (AX < FNodes[i].X + FNodes[i].W) and
       (AY >= FNodes[i].Y) and (AY < FNodes[i].Y + FNodes[i].H) then
    begin
      Result := i;
      Exit;
    end;
end;

function TDocModel.NodeKind(I: Integer): TWidgetKind;
begin
  Result := FNodes[I].Kind;
end;

function TDocModel.NodeCaption(I: Integer): AnsiString;
begin
  Result := FNodes[I].Caption;
end;

function TDocModel.NodeParent(I: Integer): Integer;
begin
  Result := FNodes[I].Parent;
end;

function TDocModel.NodeX(I: Integer): Integer;
begin
  Result := FNodes[I].X;
end;

function TDocModel.NodeY(I: Integer): Integer;
begin
  Result := FNodes[I].Y;
end;

function TDocModel.NodeW(I: Integer): Integer;
begin
  Result := FNodes[I].W;
end;

function TDocModel.NodeH(I: Integer): Integer;
begin
  Result := FNodes[I].H;
end;

function TDocModel.KindName(K: TWidgetKind): AnsiString;
begin
  case K of
    wkForm:     Result := 'Form';
    wkPanel:    Result := 'Panel';
    wkButton:   Result := 'Button';
    wkLabel:    Result := 'Label';
    wkEdit:     Result := 'Edit';
    wkMemo:     Result := 'Memo';
    wkListBox:  Result := 'ListBox';
    wkCheckBox: Result := 'CheckBox';
  else
    Result := '?';
  end;
end;

end.
