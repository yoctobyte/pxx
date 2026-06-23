unit controls;

interface

uses typinfo, classes_lite;

type
  TControl = class(TComponent)
  private
    FHandle: Pointer;
    FParent: TControl;
    FLeft, FTop, FWidth, FHeight: Integer;
    FCaption: string;
    FOnClick: TMethod;
    FOnMouseDown: TMethod;
    FOnMouseUp: TMethod;
    FOnMouseMove: TMethod;
    FOnKeyDown: TMethod;
    procedure SetParent(p: TControl);
    procedure SetLeft(v: Integer);
    procedure SetTop(v: Integer);
    procedure SetWidth(v: Integer);
    procedure SetHeight(v: Integer);
    procedure SetCaption(const s: string);
  public
    procedure CreateHandle; virtual;
    procedure HandleNeeded;
    function Realize: Integer; virtual;
    function ApplyCaption: Integer; virtual;
    procedure Show;
    procedure Invalidate;
    procedure ConnectClick;
    procedure SetBounds(ALeft, ATop, AWidth, AHeight: Integer);
    function GetHandle: Pointer;
    property Handle: Pointer read FHandle write FHandle;
    property Parent: TControl read FParent write SetParent;
  published
    property Left: Integer read FLeft write SetLeft;
    property Top: Integer read FTop write SetTop;
    property Width: Integer read FWidth write SetWidth;
    property Height: Integer read FHeight write SetHeight;
    property Caption: string read FCaption write SetCaption;
    property OnClick: TMethod read FOnClick write FOnClick;
    { Mouse events: procedure(Sender: TControl; Button, X, Y: Integer) of object.
      Button is 1=left,2=middle,3=right (0 for moves). }
    property OnMouseDown: TMethod read FOnMouseDown write FOnMouseDown;
    property OnMouseUp: TMethod read FOnMouseUp write FOnMouseUp;
    property OnMouseMove: TMethod read FOnMouseMove write FOnMouseMove;
    { Keyboard: procedure(Sender: TControl; KeyCode: Integer) of object — KeyCode
      is the GDK keyval (the widget must be focusable + focused). }
    property OnKeyDown: TMethod read FOnKeyDown write FOnKeyDown;
  end;

  TWinControl = class(TControl)
  end;

implementation

uses uwidgetset;

procedure TControl.SetLeft(v: Integer);
begin
  if FLeft <> v then
  begin
    FLeft := v;
    if FHandle <> nil then
      WidgetSet.SetBounds(Self, FLeft, FTop, FWidth, FHeight);
  end;
end;

procedure TControl.SetTop(v: Integer);
begin
  if FTop <> v then
  begin
    FTop := v;
    if FHandle <> nil then
      WidgetSet.SetBounds(Self, FLeft, FTop, FWidth, FHeight);
  end;
end;

procedure TControl.SetWidth(v: Integer);
begin
  if FWidth <> v then
  begin
    FWidth := v;
    if FHandle <> nil then
      WidgetSet.SetBounds(Self, FLeft, FTop, FWidth, FHeight);
  end;
end;

procedure TControl.SetHeight(v: Integer);
begin
  if FHeight <> v then
  begin
    FHeight := v;
    if FHandle <> nil then
      WidgetSet.SetBounds(Self, FLeft, FTop, FWidth, FHeight);
  end;
end;

procedure TControl.SetCaption(const s: string);
begin
  FCaption := s;
  if FHandle <> nil then
    Self.ApplyCaption;
end;

procedure TControl.SetBounds(ALeft, ATop, AWidth, AHeight: Integer);
begin
  FLeft := ALeft;
  FTop := ATop;
  FWidth := AWidth;
  FHeight := AHeight;
  if FHandle <> nil then
    WidgetSet.SetBounds(Self, FLeft, FTop, FWidth, FHeight);
end;

procedure TControl.Invalidate;
begin
  if FHandle <> nil then
    WidgetSet.Invalidate(Self);
end;

procedure TControl.ConnectClick;
begin
  WidgetSet.ConnectClick(Self);
end;

function TControl.GetHandle: Pointer;
begin
  Result := FHandle;
end;

procedure TControl.CreateHandle;
begin
  { Base: no widget. }
end;

procedure TControl.HandleNeeded;
begin
  if FHandle = nil then
    Self.CreateHandle;
end;

function GetInstanceClassName(inst: Pointer): string;
var
  reg: PRegistry;
  entries: PRTTIEntry;
  vmt: Pointer;
  i: Integer;
begin
  Result := '';
  if inst = nil then Exit;
  vmt := PPointer(inst)^;
  reg := __rttireg();
  if reg = nil then Exit;
  entries := @reg^.Dummy;
  for i := 0 to Integer(reg^.Count) - 1 do
  begin
    if entries[i].RTTIPtr^.VMTPtr = vmt then
    begin
      Result := entries[i].NamePtr^;
      Exit;
    end;
  end;
end;

function IsSubclassOf(cls: PClassRTTI; const ABaseName: string): Boolean;
var
  curr: PClassRTTI;
begin
  Result := False;
  curr := cls;
  while curr <> nil do
  begin
    if curr^.NamePtr^ = ABaseName then
    begin
      Result := True;
      Exit;
    end;
    curr := PClassRTTI(curr^.ParentRTTI);
  end;
end;

function TControl.Realize: Integer;
var i, n: Integer; c: TComponent; ctl: TControl; cls: PClassRTTI;
begin
  Self.HandleNeeded;
  Self.ApplyCaption;
  if (FLeft <> 0) or (FTop <> 0) or (FWidth <> 0) or (FHeight <> 0) then
    WidgetSet.SetBounds(Self, FLeft, FTop, FWidth, FHeight);
    
  n := ChildCount;
  for i := 0 to n - 1 do
  begin
    c := Child(i);
    cls := GetClass(GetInstanceClassName(Pointer(c)));
    if IsSubclassOf(cls, 'TControl') then
    begin
      ctl := TControl(c);
      ctl.Realize;
      WidgetSet.SetParent(ctl, Self);
    end;
  end;
  Result := 0;
end;

function TControl.ApplyCaption: Integer;
begin
  if FHandle <> nil then
    WidgetSet.SetText(Self, FCaption);
  Result := 0;
end;

procedure TControl.SetParent(p: TControl);
begin
  FParent := p;
  if p <> nil then
  begin
    p.AddChild(Self);
  end;
end;

procedure TControl.Show;
begin
  WidgetSet.ShowWidget(Self);
end;

end.
