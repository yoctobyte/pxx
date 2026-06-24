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
    wkMemo, wkListBox, wkCheckBox,
    { non-visual components — live in the form's tray, not on the canvas }
    wkTimer, wkMenu);

  TDocNode = record
    Kind: TWidgetKind;
    Caption: AnsiString;
    Parent: Integer;   { index into the model; -1 = the form/root }
    X, Y, W, H: Integer;
    { extra published properties beyond the modelled ones (Interval, Enabled, …),
      kept verbatim as name=value so they survive a .lfm round-trip and feed the
      RTTI inspector. Parallel arrays. }
    PropN: array of AnsiString;
    PropV: array of AnsiString;
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
    procedure SetNodeCaption(I: Integer; const ACaption: AnsiString);
    { remove node I and all its descendants; compact and remap Parent indices. }
    procedure DeleteNode(I: Integer);
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
    { non-visual components have no canvas geometry — the face renders them in a
      tray strip, not as a positioned/resizable box. }
    function IsNonVisual(K: TWidgetKind): Boolean;
    { extra-property bag (verbatim name=value). SetNodeProp overwrites an existing
      name or appends. }
    procedure SetNodeProp(I: Integer; const AName, AVal: AnsiString);
    function NodePropCount(I: Integer): Integer;
    function NodePropName(I, J: Integer): AnsiString;
    function NodePropVal(I, J: Integer): AnsiString;
    function NodePropByName(I: Integer; const AName: AnsiString): AnsiString;
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

procedure TDocModel.SetNodeCaption(I: Integer; const ACaption: AnsiString);
begin
  if (I < 0) or (I >= FCount) then Exit;
  FNodes[I].Caption := ACaption;
end;

procedure TDocModel.DeleteNode(I: Integer);
var
  dead: array of Boolean;
  oldToNew: array of Integer;
  j, n, p: Integer;
begin
  if (I < 0) or (I >= FCount) then Exit;

  SetLength(dead, FCount);
  SetLength(oldToNew, FCount);
  for j := 0 to FCount - 1 do dead[j] := False;
  dead[I] := True;
  { a child's index is always > its parent's (parent must exist at AddNode), so
    one forward pass propagates the deletion to all descendants. }
  for j := 0 to FCount - 1 do
    if (FNodes[j].Parent >= 0) and dead[FNodes[j].Parent] then dead[j] := True;

  { compact survivors in place, recording old->new indices }
  n := 0;
  for j := 0 to FCount - 1 do
    if not dead[j] then
    begin
      if n <> j then FNodes[n] := FNodes[j];
      oldToNew[j] := n;
      Inc(n);
    end
    else
      oldToNew[j] := -1;

  { remap parent links to the new indices }
  for j := 0 to n - 1 do
  begin
    p := FNodes[j].Parent;
    if p >= 0 then FNodes[j].Parent := oldToNew[p];
  end;

  FCount := n;
  SetLength(FNodes, n);
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
    wkTimer:    Result := 'Timer';
    wkMenu:     Result := 'Menu';
  else
    Result := '?';
  end;
end;

function TDocModel.IsNonVisual(K: TWidgetKind): Boolean;
begin
  IsNonVisual := (K = wkTimer) or (K = wkMenu);
end;

procedure TDocModel.SetNodeProp(I: Integer; const AName, AVal: AnsiString);
var j, n: Integer;
begin
  if (I < 0) or (I >= FCount) then Exit;
  for j := 0 to Length(FNodes[I].PropN) - 1 do
    if FNodes[I].PropN[j] = AName then
    begin
      FNodes[I].PropV[j] := AVal;
      Exit;
    end;
  n := Length(FNodes[I].PropN);
  SetLength(FNodes[I].PropN, n + 1);
  SetLength(FNodes[I].PropV, n + 1);
  FNodes[I].PropN[n] := AName;
  FNodes[I].PropV[n] := AVal;
end;

function TDocModel.NodePropCount(I: Integer): Integer;
begin
  if (I < 0) or (I >= FCount) then NodePropCount := 0
  else NodePropCount := Length(FNodes[I].PropN);
end;

function TDocModel.NodePropName(I, J: Integer): AnsiString;
begin
  NodePropName := '';
  if (I < 0) or (I >= FCount) then Exit;
  if (J >= 0) and (J < Length(FNodes[I].PropN)) then NodePropName := FNodes[I].PropN[J];
end;

function TDocModel.NodePropVal(I, J: Integer): AnsiString;
begin
  NodePropVal := '';
  if (I < 0) or (I >= FCount) then Exit;
  if (J >= 0) and (J < Length(FNodes[I].PropV)) then NodePropVal := FNodes[I].PropV[J];
end;

function TDocModel.NodePropByName(I: Integer; const AName: AnsiString): AnsiString;
var j: Integer;
begin
  NodePropByName := '';
  if (I < 0) or (I >= FCount) then Exit;
  for j := 0 to Length(FNodes[I].PropN) - 1 do
    if FNodes[I].PropN[j] = AName then
    begin
      NodePropByName := FNodes[I].PropV[j];
      Exit;
    end;
end;

end.
