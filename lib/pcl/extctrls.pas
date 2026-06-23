unit extctrls;

interface

uses classes_lite, controls, uwidgetset, typinfo, graphics, gtk3_c;

type
  TPanel = class(TWinControl)
  public
    constructor Create(AOwner: TComponent); override;
    procedure CreateHandle; override;
  end;

  TTimer = class(TComponent)
  private
    FInterval: Integer;
    FEnabled: Boolean;
    FOnTimer: TMethod;
    FTimerId: LongWord;
    procedure SetEnabled(v: Boolean);
    procedure SetInterval(v: Integer);
    procedure UpdateTimer;
  public
    constructor Create(AOwner: TComponent); override;
    destructor Destroy;
  published
    property Interval: Integer read FInterval write SetInterval;
    property Enabled: Boolean read FEnabled write SetEnabled;
    property OnTimer: TMethod read FOnTimer write FOnTimer;
  end;

  TPaintBox = class(TControl)
  private
    FCanvas: TCanvas;
    FOnPaint: TMethod;
  public
    constructor Create(AOwner: TComponent); override;
    destructor Destroy;
    procedure CreateHandle; override;
    property Canvas: TCanvas read FCanvas;
  published
    property OnPaint: TMethod read FOnPaint write FOnPaint;
  end;

  { TPaned — a container split by a draggable handle into two resizable panes.
    Give it exactly two children (the first fills pane 1, the second pane 2).
    Create is horizontal (side-by-side, vertical handle); CreateVertical stacks
    them (horizontal handle). Position is the handle offset in pixels from the
    top/left. Unlike TPanel, children are NOT placed by absolute coords — gtk's
    paned sizes them and the user drags the handle between them. }
  TPaned = class(TWinControl)
  private
    FVertical: Boolean;
    FPosition: Integer;
    FCollapsedPane: Integer;   { 0 = none, 1 = pane1 collapsed, 2 = pane2 collapsed }
    FRestorePos: Integer;      { handle position remembered across a collapse }
    procedure SetPosition(v: Integer);
    function AxisSize: Integer; { allocated span along the split axis }
  public
    constructor Create(AOwner: TComponent); override;
    procedure CreateHandle; override;
    function Realize: Integer; override;
    function ActualPosition: Integer;   { live handle position from the widget }
    { Collapse a pane to (near) zero, remembering the current handle position;
      Restore puts it back. AStrip leaves that many px visible (0 = fully gone).
      Toggle collapses APane if open, else restores. APane is 1 or 2. }
    procedure Collapse(APane: Integer; AStrip: Integer);
    procedure Restore;
    procedure Toggle(APane: Integer; AStrip: Integer);
    function CollapsedPane: Integer;    { 0 none, else which pane is collapsed }
  published
    { Set Vertical (and optionally Position) before the form is realized — the
      paned handle is built lazily at Realize time. }
    property Position: Integer read FPosition write SetPosition;
    property Vertical: Boolean read FVertical write FVertical;
  end;

implementation

{ TPanel }

constructor TPanel.Create(AOwner: TComponent);
begin
  inherited Create(AOwner);
  Self.HandleNeeded;
end;

procedure TPanel.CreateHandle;
begin
  Self.Handle := WidgetSet.CreatePanel(Self);
end;

{ TPaned }

constructor TPaned.Create(AOwner: TComponent);
begin
  inherited Create(AOwner);
  { Lazy handle: Vertical must be known at CreateHandle, so defer to Realize. }
  FVertical := False;
  FPosition := 0;
  FCollapsedPane := 0;
  FRestorePos := 0;
end;

procedure TPaned.CreateHandle;
var orient: Integer;
begin
  { Talk to gtk directly here (like graphics.pas) rather than through a
    WidgetSet method: adding new virtual methods to TWidgetSet currently
    miscompiles their object argument — see
    docs/progress/backlog/bug-widgetset-virtual-arg-corruption.md. gtk
    orientation: 0 = horizontal (side-by-side, vertical handle), 1 = vertical. }
  if FVertical then orient := 1 else orient := 0;
  Self.Handle := gtk_paned_new(orient);
end;

function TPaned.Realize: Integer;
begin
  { inherited packs the two children; only then is a handle position valid —
    setting it on an empty paned crashes gtk. }
  Result := inherited Realize;
  if (FPosition <> 0) and (Self.Handle <> nil) then
    gtk_paned_set_position(Self.Handle, FPosition);
end;

procedure TPaned.SetPosition(v: Integer);
begin
  FPosition := v;
  if Self.Handle <> nil then
    gtk_paned_set_position(Self.Handle, v);
end;

function TPaned.ActualPosition: Integer;
begin
  if Self.Handle <> nil then
    Result := gtk_paned_get_position(Self.Handle)
  else
    Result := 0;
end;

{ the paned's span along its split axis (width if horizontal, height if vertical) }
function TPaned.AxisSize: Integer;
begin
  if Self.Handle = nil then Result := 0
  else if FVertical then Result := gtk_widget_get_allocated_height(Self.Handle)
  else Result := gtk_widget_get_allocated_width(Self.Handle);
end;

procedure TPaned.Collapse(APane: Integer; AStrip: Integer);
var sz: Integer;
begin
  if Self.Handle = nil then Exit;
  if FCollapsedPane <> 0 then Restore;          { only one collapse at a time }
  FRestorePos := gtk_paned_get_position(Self.Handle);
  if APane = 1 then
    SetPosition(AStrip)                          { pane1 shrinks to the strip }
  else
  begin
    sz := AxisSize;
    if sz <= 0 then sz := FRestorePos;           { not allocated yet: best effort }
    SetPosition(sz - AStrip);                    { pane2 shrinks to the strip }
  end;
  FCollapsedPane := APane;
end;

procedure TPaned.Restore;
begin
  if FCollapsedPane = 0 then Exit;
  SetPosition(FRestorePos);
  FCollapsedPane := 0;
end;

procedure TPaned.Toggle(APane: Integer; AStrip: Integer);
begin
  if FCollapsedPane = APane then Restore
  else Collapse(APane, AStrip);
end;

function TPaned.CollapsedPane: Integer;
begin
  Result := FCollapsedPane;
end;

{ TTimer }

constructor TTimer.Create(AOwner: TComponent);
begin
  inherited Create(AOwner);
  FInterval := 1000;
  FEnabled := True;
  FTimerId := 0;
  Self.UpdateTimer;
end;

destructor TTimer.Destroy;
begin
  FEnabled := False;
  Self.UpdateTimer;
end;

procedure TTimer.SetEnabled(v: Boolean);
begin
  if FEnabled <> v then
  begin
    FEnabled := v;
    Self.UpdateTimer;
  end;
end;

procedure TTimer.SetInterval(v: Integer);
begin
  if FInterval <> v then
  begin
    FInterval := v;
    Self.UpdateTimer;
  end;
end;

procedure TTimer.UpdateTimer;
begin
  if FTimerId <> 0 then
  begin
    WidgetSet.StopTimer(FTimerId);
    FTimerId := 0;
  end;
  if FEnabled and (FInterval > 0) then
  begin
    FTimerId := WidgetSet.StartTimer(FInterval, nil, Self);
  end;
end;

{ TPaintBox }

constructor TPaintBox.Create(AOwner: TComponent);
begin
  inherited Create(AOwner);
  FCanvas := TCanvas.Create;
  Self.HandleNeeded;
end;

destructor TPaintBox.Destroy;
begin
  FCanvas.Destroy;
end;

procedure TPaintBox.CreateHandle;
begin
  { STOPGAP (revert when urgent/bug-metaclass-new-getclass-vmt lands and the
    streamer constructs via the virtual ctor): a streamed paintbox is made with
    CreateInstance, which skips Create, so FCanvas is nil and the draw trampoline
    would deref nil. CreateHandle runs at Realize for streamed + normal instances
    alike — ensure the Canvas here. }
  if FCanvas = nil then FCanvas := TCanvas.Create;
  Self.Handle := WidgetSet.CreatePaintBox(Self);
end;

end.
