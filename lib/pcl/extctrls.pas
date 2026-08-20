{ SPDX-License-Identifier: Zlib }
unit extctrls;

{$MODE PXX}   { our dialect; the FPC-parity strict-* flags do not judge this file }
interface

uses classes_lite, controls, uwidgetset, typinfo, graphics, stdctrls;

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

  { TBox — a stacking container: children are packed in order along one
    axis (no absolute coords, no draggable handle — unlike TPaned, any number of
    children). Horizontal by default; set Vertical before adding children (the
    handle is built lazily at CreateHandle). Each child packs with Expand=False,
    Fill=False by default, so children keep their natural size — set Vertical /
    Spacing before use; per-child expand is not yet exposed. }
  TBox = class(TWinControl)
  private
    FVertical: Boolean;
    FSpacing: Integer;
  public
    constructor Create(AOwner: TComponent); override;
    procedure CreateHandle; override;
  published
    property Vertical: Boolean read FVertical write FVertical;
    property Spacing: Integer read FSpacing write FSpacing;
  end;

  { TTabBar — a Lazarus-style tabbed component bar: a notebook whose pages
    are horizontal button rows (feature-eliah-component-tabbar). Built on the
    WidgetSet seam. AddTab appends a named tab; AddButton drops a
    real TButton into a tab's row (so the normal OnClick trampoline serves it)
    and returns it. Buttons keep their natural size and pack left-to-right;
    icons are caption placeholders until per-component glyphs exist. }
  TTabBar = class(TWinControl)
  private
    FPages: array of Pointer;   { the hbox of each tab, in AddTab order }
  public
    constructor Create(AOwner: TComponent); override;
    procedure CreateHandle; override;
    function AddTab(const ACaption: string): Integer;
    function AddButton(ATab: Integer; const ACaption: string; AOnClick: TMethod): TButton;
    function TabCount: Integer;
    { the visible tab index (-1 when empty) }
    function ActiveTab: Integer;
    procedure SetActiveTab(AIndex: Integer);
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

{ Through the WidgetSet, not gtk directly. The old comment here said new
  TWidgetSet virtuals miscompiled their object argument — that bug
  (bug-widgetset-virtual-arg-corruption) is resolved, so the avoidance it
  justified is retired and this unit no longer knows what a toolkit is. }
procedure TPaned.CreateHandle;
begin
  Self.Handle := WidgetSet.CreatePaned(FVertical);
end;

function TPaned.Realize: Integer;
begin
  { inherited packs the two children; only then is a handle position valid —
    setting it on an empty paned crashes gtk. }
  Result := inherited Realize;
  if (FPosition <> 0) and (Self.Handle <> nil) then
    WidgetSet.PanedSetPosition(Self.Handle, FPosition);
end;

procedure TPaned.SetPosition(v: Integer);
begin
  FPosition := v;
  if Self.Handle <> nil then
    WidgetSet.PanedSetPosition(Self.Handle, v);
end;

function TPaned.ActualPosition: Integer;
begin
  if Self.Handle <> nil then
    Result := WidgetSet.PanedGetPosition(Self.Handle)
  else
    Result := 0;
end;

{ the paned's span along its split axis (width if horizontal, height if vertical) }
function TPaned.AxisSize: Integer;
begin
  if Self.Handle = nil then Result := 0
  else if FVertical then Result := WidgetSet.HandleHeight(Self.Handle)
  else Result := WidgetSet.HandleWidth(Self.Handle);
end;

procedure TPaned.Collapse(APane: Integer; AStrip: Integer);
var sz: Integer; ch: Pointer;
begin
  if Self.Handle = nil then Exit;
  if FCollapsedPane <> 0 then Restore;          { only one collapse at a time }
  FRestorePos := WidgetSet.PanedGetPosition(Self.Handle);
  if AStrip > 0 then
  begin
    { strip collapse: leave AStrip px visible by moving the handle to the edge }
    if APane = 1 then SetPosition(AStrip);
    if APane = 2 then
    begin
      sz := AxisSize;
      if sz <= 0 then sz := FRestorePos;
      SetPosition(sz - AStrip);
    end;
  end
  else
  begin
    { full collapse: hide the pane's child so the sibling takes all the space
      (robust regardless of shrink / allocation) }
    ch := WidgetSet.PanedChild(Self.Handle, APane);
    WidgetSet.HideHandle(ch);
  end;
  FCollapsedPane := APane;
end;

procedure TPaned.Restore;
var ch: Pointer;
begin
  if FCollapsedPane = 0 then Exit;
  ch := WidgetSet.PanedChild(Self.Handle, FCollapsedPane);
  WidgetSet.ShowHandle(ch);                     { no-op if it was a strip collapse }
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

{ TBox }

constructor TBox.Create(AOwner: TComponent);
begin
  inherited Create(AOwner);
  FVertical := False;
  FSpacing := 0;
end;

procedure TBox.CreateHandle;
begin
  Self.Handle := WidgetSet.CreateBox(FVertical, FSpacing);
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
  Self.Handle := WidgetSet.CreatePaintBox(Self);
end;

{ TTabBar }

constructor TTabBar.Create(AOwner: TComponent);
begin
  inherited Create(AOwner);
  SetLength(FPages, 0);
  Self.HandleNeeded;
end;

procedure TTabBar.CreateHandle;
begin
  Self.Handle := WidgetSet.CreateNotebook;
end;

function TTabBar.AddTab(const ACaption: string): Integer;
var
  box: Pointer;
begin
  { the widgetset builds the page's content row AND its label; this unit never
    sees a label widget, which is the whole point of the seam }
  box := WidgetSet.NotebookAddPage(Self.Handle, ACaption);
  SetLength(FPages, Length(FPages) + 1);
  FPages[Length(FPages) - 1] := box;
  AddTab := Length(FPages) - 1;
end;

function TTabBar.AddButton(ATab: Integer; const ACaption: string; AOnClick: TMethod): TButton;
var
  b: TButton;
begin
  AddButton := nil;
  if (ATab < 0) or (ATab >= Length(FPages)) then Exit;
  b := TButton.Create(Self);
  b.Caption := ACaption;
  { pack into the tab's row instead of a fixed-coord parent; the button's
    handle already exists (TButton.Create does HandleNeeded) and is wired to
    the click trampoline, so OnClick works as on any button }
  WidgetSet.BoxPack(FPages[ATab], b.Handle, False, False, 2);
  WidgetSet.ShowHandle(b.Handle);
  b.OnClick := AOnClick;
  AddButton := b;
end;

function TTabBar.TabCount: Integer;
begin
  TabCount := Length(FPages);
end;

function TTabBar.ActiveTab: Integer;
begin
  ActiveTab := WidgetSet.NotebookGetPage(Self.Handle);
end;

procedure TTabBar.SetActiveTab(AIndex: Integer);
begin
  WidgetSet.NotebookSetPage(Self.Handle, AIndex);
end;

end.
