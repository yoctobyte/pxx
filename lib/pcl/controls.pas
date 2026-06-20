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
    procedure SetParent(p: TControl);
    procedure SetLeft(v: Integer);
    procedure SetTop(v: Integer);
    procedure SetWidth(v: Integer);
    procedure SetHeight(v: Integer);
    procedure SetCaption(const s: string);
  public
    procedure CreateHandle; virtual;
    procedure HandleNeeded;
    procedure Realize;
    procedure ApplyCaption; virtual;
    procedure Show;
    procedure ConnectClick;
    procedure SetBounds(ALeft, ATop, AWidth, AHeight: Integer);
    property Handle: Pointer read FHandle write FHandle;
    property Parent: TControl read FParent write SetParent;
  published
    property Left: Integer read FLeft write SetLeft;
    property Top: Integer read FTop write SetTop;
    property Width: Integer read FWidth write SetWidth;
    property Height: Integer read FHeight write SetHeight;
    property Caption: string read FCaption write SetCaption;
    property OnClick: TMethod read FOnClick write FOnClick;
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

procedure TControl.ConnectClick;
begin
  WidgetSet.ConnectClick(Self);
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

procedure TControl.Realize;
var i, n: Integer; c: TComponent; ctl: TControl;
begin
  Self.HandleNeeded;
  Self.ApplyCaption;
  if (FLeft <> 0) or (FTop <> 0) or (FWidth <> 0) or (FHeight <> 0) then
    WidgetSet.SetBounds(Self, FLeft, FTop, FWidth, FHeight);
    
  n := ChildCount;
  for i := 0 to n - 1 do
  begin
    c := Child(i);
    ctl := c;
    ctl.Realize;
    WidgetSet.SetParent(ctl, Self);
  end;
end;

procedure TControl.ApplyCaption;
begin
  if FHandle <> nil then
    WidgetSet.SetText(Self, FCaption);
end;

procedure TControl.SetParent(p: TControl);
begin
  writeln('TControl.SetParent start: Self=', Int64(Self), ' p=', Int64(p));
  FParent := p;
  if p <> nil then
  begin
    writeln('TControl.SetParent calling AddChild');
    p.AddChild(Self);
    writeln('TControl.SetParent returned from AddChild');
  end;
  writeln('TControl.SetParent done');
end;

procedure TControl.Show;
begin
  WidgetSet.ShowWidget(Self);
end;

end.
