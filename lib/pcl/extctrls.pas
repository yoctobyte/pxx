unit extctrls;

interface

uses classes_lite, controls, uwidgetset, typinfo, graphics;

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
