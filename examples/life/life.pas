program life;

{$define PXX_MANAGED_STRING}

uses gtk3, controls, stdctrls, forms, extctrls, graphics, random, bitset, sysutils;

type
  TLifeHandler = class
  private
    FCurrentGrid: TBitArray;
    FNextGrid: TBitArray;
    FGeneration: Integer;
    FRunning: Boolean;
    FBitmap: TBitmap;
    FPaintBox: TPaintBox;
    FTimer: TTimer;
    FStartStopBtn: TButton;
    FGenLabel: TLabel;
    
    procedure UpdateLabel;
    procedure RenderToBitmap;
  public
    constructor Create(APaintBox: TPaintBox; ATimer: TTimer; AStartStopBtn: TButton; AGenLabel: TLabel);
    destructor Destroy;
    
    procedure OnPaint(Sender: TControl; Canvas: TCanvas);
    procedure OnTimer(Sender: TObject);
    procedure OnStartStop(Sender: TObject);
    procedure OnStep(Sender: TObject);
    procedure OnClear(Sender: TObject);
    procedure OnRandom(Sender: TObject);
    procedure OnGliderPreset(Sender: TObject);
    procedure OnGosperPreset(Sender: TObject);
    
    procedure SetCellState(x, y: Integer; alive: Boolean);
    function GetCellState(x, y: Integer): Boolean;
    procedure Step;
    property Generation: Integer read FGeneration;
  end;

constructor TLifeHandler.Create(APaintBox: TPaintBox; ATimer: TTimer; AStartStopBtn: TButton; AGenLabel: TLabel);
begin
  FPaintBox := APaintBox;
  FTimer := ATimer;
  FStartStopBtn := AStartStopBtn;
  FGenLabel := AGenLabel;
  FGeneration := 0;
  FRunning := False;
  
  BitArrayInit(FCurrentGrid, 80 * 50);
  BitArrayInit(FNextGrid, 80 * 50);
  
  FBitmap := TBitmap.Create;
  FBitmap.Width := 640;
  FBitmap.Height := 400;
  FBitmap.Clear($001A1A1A);
  
  Self.UpdateLabel;
end;

destructor TLifeHandler.Destroy;
begin
  FBitmap.Destroy;
end;

procedure TLifeHandler.UpdateLabel;
begin
  FGenLabel.Caption := 'Generation: ' + IntToStr(FGeneration);
end;

procedure TLifeHandler.SetCellState(x, y: Integer; alive: Boolean);
begin
  if (x >= 0) and (x < 80) and (y >= 0) and (y < 50) then
  begin
    if alive then
      BitArraySetBit(FCurrentGrid, y * 80 + x)
    else
      BitArrayClearBit(FCurrentGrid, y * 80 + x);
  end;
end;

function TLifeHandler.GetCellState(x, y: Integer): Boolean;
begin
  if (x < 0) or (x >= 80) or (y < 0) or (y >= 50) then
    Result := False
  else
    Result := BitArrayTestBit(FCurrentGrid, y * 80 + x);
end;

procedure TLifeHandler.RenderToBitmap;
var
  x, y, cx, cy: Integer;
  alive: Boolean;
  color: TColor;
begin
  for y := 0 to 49 do
  begin
    for x := 0 to 79 do
    begin
      alive := BitArrayTestBit(FCurrentGrid, y * 80 + x);
      if alive then
        color := $0000FF00 { Opaque Green cells }
      else
        color := $001A1A1A; { Opaque Dark Grey background }
        
      { Draw 8x8 block }
      for cy := y * 8 to y * 8 + 7 do
      begin
        for cx := x * 8 to x * 8 + 7 do
        begin
          { Add a subtle grid/border by making the bottom/right pixel of each cell black }
          if (cx = x * 8 + 7) or (cy = y * 8 + 7) then
            FBitmap.SetPixel(cx, cy, $000D0D0D)
          else
            FBitmap.SetPixel(cx, cy, color);
        end;
      end;
    end;
  end;
end;

procedure TLifeHandler.Step;
var
  x, y, neighbors: Integer;
  alive: Boolean;
  tempBits: array of Integer;
  tempLen: Integer;
begin
  for y := 0 to 49 do
  begin
    for x := 0 to 79 do
    begin
      { Count neighbors (toroidal/wrapping grid) }
      neighbors := 0;
      
      { Neighbor 1: top-left }
      if Self.GetCellState((x - 1 + 80) mod 80, (y - 1 + 50) mod 50) then neighbors := neighbors + 1;
      { Neighbor 2: top }
      if Self.GetCellState(x, (y - 1 + 50) mod 50) then neighbors := neighbors + 1;
      { Neighbor 3: top-right }
      if Self.GetCellState((x + 1) mod 80, (y - 1 + 50) mod 50) then neighbors := neighbors + 1;
      { Neighbor 4: left }
      if Self.GetCellState((x - 1 + 80) mod 80, y) then neighbors := neighbors + 1;
      { Neighbor 5: right }
      if Self.GetCellState((x + 1) mod 80, y) then neighbors := neighbors + 1;
      { Neighbor 6: bottom-left }
      if Self.GetCellState((x - 1 + 80) mod 80, (y + 1) mod 50) then neighbors := neighbors + 1;
      { Neighbor 7: bottom }
      if Self.GetCellState(x, (y + 1) mod 50) then neighbors := neighbors + 1;
      { Neighbor 8: bottom-right }
      if Self.GetCellState((x + 1) mod 80, (y + 1) mod 50) then neighbors := neighbors + 1;
      
      alive := BitArrayTestBit(FCurrentGrid, y * 80 + x);
      if alive then
      begin
        if (neighbors = 2) or (neighbors = 3) then
          BitArraySetBit(FNextGrid, y * 80 + x)
        else
          BitArrayClearBit(FNextGrid, y * 80 + x);
      end
      else
      begin
        if neighbors = 3 then
          BitArraySetBit(FNextGrid, y * 80 + x)
        else
          BitArrayClearBit(FNextGrid, y * 80 + x);
      end;
    end;
  end;
  
  tempBits := FCurrentGrid.bits;
  tempLen := FCurrentGrid.len;
  
  FCurrentGrid.bits := FNextGrid.bits;
  FCurrentGrid.len := FNextGrid.len;
  
  FNextGrid.bits := tempBits;
  FNextGrid.len := tempLen;
  
  FGeneration := FGeneration + 1;
  Self.UpdateLabel;
  Self.RenderToBitmap;
  FPaintBox.Invalidate;
end;

procedure TLifeHandler.OnPaint(Sender: TControl; Canvas: TCanvas);
begin
  if Canvas <> nil then
  begin
    Canvas.Draw(0, 0, FBitmap);
  end;
end;

procedure TLifeHandler.OnTimer(Sender: TObject);
begin
  if FRunning then
  begin
    Self.Step;
  end;
end;

procedure TLifeHandler.OnStartStop(Sender: TObject);
begin
  FRunning := not FRunning;
  if FRunning then
  begin
    FStartStopBtn.Caption := 'Stop';
    FTimer.Enabled := True;
  end
  else
  begin
    FStartStopBtn.Caption := 'Start';
    FTimer.Enabled := False;
  end;
end;

procedure TLifeHandler.OnStep(Sender: TObject);
begin
  if not FRunning then
  begin
    Self.Step;
  end;
end;

procedure TLifeHandler.OnClear(Sender: TObject);
var
  i: Integer;
begin
  FRunning := False;
  FStartStopBtn.Caption := 'Start';
  FTimer.Enabled := False;
  FGeneration := 0;
  Self.UpdateLabel;
  
  for i := 0 to FCurrentGrid.len - 1 do
  begin
    BitArrayClearBit(FCurrentGrid, i);
    BitArrayClearBit(FNextGrid, i);
  end;
  
  Self.RenderToBitmap;
  FPaintBox.Invalidate;
end;

procedure TLifeHandler.OnRandom(Sender: TObject);
var
  i: Integer;
begin
  FGeneration := 0;
  Self.UpdateLabel;
  
  for i := 0 to FCurrentGrid.len - 1 do
  begin
    if Random(100) < 20 then { 20% density }
      BitArraySetBit(FCurrentGrid, i)
    else
      BitArrayClearBit(FCurrentGrid, i);
    BitArrayClearBit(FNextGrid, i);
  end;
  
  Self.RenderToBitmap;
  FPaintBox.Invalidate;
end;

procedure TLifeHandler.OnGliderPreset(Sender: TObject);
begin
  { Clear first }
  Self.OnClear(nil);
  
  { Place a glider near the top-left }
  Self.SetCellState(11, 10, True);
  Self.SetCellState(12, 11, True);
  Self.SetCellState(10, 12, True);
  Self.SetCellState(11, 12, True);
  Self.SetCellState(12, 12, True);
  
  Self.RenderToBitmap;
  FPaintBox.Invalidate;
end;

procedure TLifeHandler.OnGosperPreset(Sender: TObject);
begin
  { Clear first }
  Self.OnClear(nil);
  
  { Gosper Glider Gun preset }
  { Left block }
  Self.SetCellState(1, 5, True);
  Self.SetCellState(1, 6, True);
  Self.SetCellState(2, 5, True);
  Self.SetCellState(2, 6, True);
  
  { Left gun shape }
  Self.SetCellState(11, 5, True);
  Self.SetCellState(11, 6, True);
  Self.SetCellState(11, 7, True);
  Self.SetCellState(12, 4, True);
  Self.SetCellState(12, 8, True);
  Self.SetCellState(13, 3, True);
  Self.SetCellState(13, 9, True);
  Self.SetCellState(14, 3, True);
  Self.SetCellState(14, 9, True);
  Self.SetCellState(15, 6, True);
  Self.SetCellState(16, 4, True);
  Self.SetCellState(16, 8, True);
  Self.SetCellState(17, 5, True);
  Self.SetCellState(17, 6, True);
  Self.SetCellState(17, 7, True);
  Self.SetCellState(18, 6, True);
  
  { Right gun shape }
  Self.SetCellState(21, 3, True);
  Self.SetCellState(21, 4, True);
  Self.SetCellState(21, 5, True);
  Self.SetCellState(22, 3, True);
  Self.SetCellState(22, 4, True);
  Self.SetCellState(22, 5, True);
  Self.SetCellState(23, 2, True);
  Self.SetCellState(23, 6, True);
  Self.SetCellState(25, 1, True);
  Self.SetCellState(25, 2, True);
  Self.SetCellState(25, 6, True);
  Self.SetCellState(25, 7, True);
  
  { Right block }
  Self.SetCellState(35, 3, True);
  Self.SetCellState(35, 4, True);
  Self.SetCellState(36, 3, True);
  Self.SetCellState(36, 4, True);
  
  Self.RenderToBitmap;
  FPaintBox.Invalidate;
end;

function AutoQuit(data: Pointer): Integer; cdecl;
var
  h: TLifeHandler;
begin
  h := TLifeHandler(data);
  writeln('Smoke test auto-quit. Generation count: ', h.Generation);
  gtk_main_quit;
  AutoQuit := 0;
end;

var
  Form1: TForm;
  PaintBox: TPaintBox;
  Timer: TTimer;
  StartStopBtn: TButton;
  StepBtn: TButton;
  ClearBtn: TButton;
  RandomBtn: TButton;
  GliderBtn: TButton;
  GosperBtn: TButton;
  GenLabel: TLabel;
  Handler: TLifeHandler;
  arg: string;

begin
  { Initialize PRNG seed }
  RandSeed(12345);

  Application.Initialize;
  
  Form1 := TForm.Create;
  Form1.Caption := 'Conway''s Game of Life';
  Form1.SetBounds(100, 100, 800, 480);
  
  PaintBox := TPaintBox.Create;
  PaintBox.Parent := Form1;
  PaintBox.SetBounds(10, 10, 640, 400);
  
  Timer := TTimer.Create;
  Timer.Interval := 50; { 50ms interval }
  Timer.Enabled := False;
  
  StartStopBtn := TButton.Create;
  StartStopBtn.Parent := Form1;
  StartStopBtn.Caption := 'Start';
  StartStopBtn.SetBounds(660, 10, 130, 30);
  
  StepBtn := TButton.Create;
  StepBtn.Parent := Form1;
  StepBtn.Caption := 'Step';
  StepBtn.SetBounds(660, 50, 130, 30);
  
  ClearBtn := TButton.Create;
  ClearBtn.Parent := Form1;
  ClearBtn.Caption := 'Clear';
  ClearBtn.SetBounds(660, 90, 130, 30);
  
  RandomBtn := TButton.Create;
  RandomBtn.Parent := Form1;
  RandomBtn.Caption := 'Random';
  RandomBtn.SetBounds(660, 130, 130, 30);
  
  GliderBtn := TButton.Create;
  GliderBtn.Parent := Form1;
  GliderBtn.Caption := 'Glider Preset';
  GliderBtn.SetBounds(660, 170, 130, 30);
  
  GosperBtn := TButton.Create;
  GosperBtn.Parent := Form1;
  GosperBtn.Caption := 'Glider Gun';
  GosperBtn.SetBounds(660, 210, 130, 30);
  
  GenLabel := TLabel.Create;
  GenLabel.Parent := Form1;
  GenLabel.Caption := 'Generation: 0';
  GenLabel.SetBounds(660, 260, 130, 30);
  
  Handler := TLifeHandler.Create(PaintBox, Timer, StartStopBtn, GenLabel);
  
  PaintBox.OnPaint := @Handler.OnPaint;
  Timer.OnTimer := @Handler.OnTimer;
  StartStopBtn.OnClick := @Handler.OnStartStop;
  StepBtn.OnClick := @Handler.OnStep;
  ClearBtn.OnClick := @Handler.OnClear;
  RandomBtn.OnClick := @Handler.OnRandom;
  GliderBtn.OnClick := @Handler.OnGliderPreset;
  GosperBtn.OnClick := @Handler.OnGosperPreset;
  
  { Start with a random grid by default }
  Handler.OnRandom(nil);
  
  if ParamCount > 0 then
  begin
    arg := ParamStr(1);
    if arg = '--smoke' then
    begin
      writeln('Running in smoke-test mode...');
      Handler.OnStartStop(nil); { Start simulating }
      g_timeout_add(500, @AutoQuit, Pointer(Handler));
    end;
  end;
  
  Application.MainForm := Form1;
  Application.Run;
  
  Handler.Destroy;
end.
