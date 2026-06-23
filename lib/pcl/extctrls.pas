unit extctrls;

interface

uses classes_lite, controls, uwidgetset, typinfo, graphics, gtk3_c;

type
  TPanel = class(TWinControl)
  public
    constructor Create;
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
    constructor Create;
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
    constructor Create;
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
    procedure SetPosition(v: Integer);
  public
    constructor Create;
    procedure CreateHandle; override;
    function Realize: Integer; override;
    function ActualPosition: Integer;   { live handle position from the widget }
  published
    { Set Vertical (and optionally Position) before the form is realized — the
      paned handle is built lazily at Realize time. }
    property Position: Integer read FPosition write SetPosition;
    property Vertical: Boolean read FVertical write FVertical;
  end;

implementation

{ TPanel }

constructor TPanel.Create;
begin
  Self.HandleNeeded;
end;

procedure TPanel.CreateHandle;
begin
  Self.Handle := WidgetSet.CreatePanel(Self);
end;

{ TPaned }

constructor TPaned.Create;
begin
  { Lazy handle: Vertical must be known at CreateHandle, so defer to Realize. }
  FVertical := False;
  FPosition := 0;
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

{ TTimer }

constructor TTimer.Create;
begin
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

constructor TPaintBox.Create;
begin
  FCanvas := TCanvas.Create;
  Self.HandleNeeded;
end;

destructor TPaintBox.Destroy;
begin
  FCanvas.Destroy;
end;

procedure TPaintBox.CreateHandle;
begin
  { a streamed paintbox (CreateInstance skips the constructor) has no Canvas, so
    the draw trampoline's Canvas.Handle would deref nil. CreateHandle runs at
    Realize for streamed and normal instances alike — make the Canvas here. }
  if FCanvas = nil then FCanvas := TCanvas.Create;
  Self.Handle := WidgetSet.CreatePaintBox(Self);
end;

end.
