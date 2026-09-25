program espide;

{ apps/ide/esp — the ESP32 face of the IDE (a working name; the faces carry
  Hebrew names chosen by the owner, and this one has none yet).

  One window: a folder tree on the left, the open file above, the build and
  serial output below. The toolbar carries the one thing an ESP board adds to
  an IDE: which chip, on which port.

    [ root ][Open] Chip:[auto v][Detect] [Save][Build+Flash][Monitor][Stop]
    status: project, its chip, the board(s) Detect found
    +--------------+--------------------------------------+
    | folder tree  |  editor                              |
    |              |--------------------------------------|
    |              |  build + flash log, then serial      |
    +--------------+--------------------------------------+

  Every decision lives in garin/espproj, which bochan tests headlessly: which
  folder is a project, which chip it builds for, which chip a board reports,
  and whether they agree. `auto` with no board REFUSES and says so; it never
  builds for a default chip. The build is delegated to the project's own
  build.sh through tools/esp_flash.sh --project, so the face holds no
  compiler flags. Children run through garin/runner's streaming form and are
  polled from a timer, so the window stays live during a minute-long flash.

  Serial ports need the dialout group. Flags:
    espide [folder]                 open folder (default examples/esp32)
    espide --gui-smoke              open, paint, quit (the suite runs it)
    espide --auto <project> [secs]  detect, build+flash, monitor secs (10),
                                    print the log to stdout, exit 0 on a
                                    flashed board: the hardware check. }

uses gtk3_c, gtk3, controls, stdctrls, extctrls, forms, sysutils,
     buffer, runner, project, espproj;

const
  W_WIN    = 1100;
  H_WIN    = 720;
  BAR_H    = 64;        { toolbar row + status row }
  W_TREE   = 260;
  H_LOG    = 260;
  TICK_MS  = 100;
  LOG_CAP  = 32000;     { the pane keeps a TAIL: setting a GtkTextView to the
                          whole of a 150 KB IDF build log on every chunk cost
                          more than the chunks arrived, so the window fell
                          minutes behind its own child (measured on the S3) }
  TREE_DEPTH = 6;

type
  TMode = (mIdle, mDetect, mBuild, mMonitor);

  TBoard = record
    Port: AnsiString;
    Chip: AnsiString;
  end;

  TEspForm = class(TForm)
  public
    RootEdit: TEdit;
    OpenBtn: TButton;
    ChipLbl: TLabel;
    ChipBox: TComboBox;
    DetectBtn, SaveBtn, BuildBtn, MonBtn, StopBtn: TButton;
    Status: TLabel;
    Split, RightSplit: TPaned;
    Tree: TListBox;
    Editor: TMemo;
    Log: TMemo;
    Ticker: TTimer;

    RepoRoot: AnsiString;
    RootDir: AnsiString;
    TreePaths: TStrArray;
    CurFile: AnsiString;       { absolute path of the file in the editor }
    CurText: AnsiString;       { its text as loaded or last saved }
    CurProject: AnsiString;    { project the selection belongs to, or '' }
    Selected: AnsiString;      { the selected tree entry, absolute }
    Boards: array of TBoard;
    Detected: Boolean;         { Detect has run since the last change }

    Mode: TMode;
    Proc: TStreamProc;
    ProcOut: AnsiString;
    DetectPorts: TStrArray;
    DetectIdx: Integer;
    BuildAfterDetect: Boolean;
    MonitorPort: AnsiString;
    LogText: AnsiString;

    AutoRun: Boolean;
    AutoSecs: Integer;
    AutoTicks: Integer;
    AutoRc: Integer;
    AutoDone: Boolean;
    InLoop: Boolean;       { Application.Run has started: quitting is legal }
    lastW: Integer;
    panedSeeded: Boolean;

    procedure AddLog(const s: AnsiString);
    procedure SetStatus(const s: AnsiString);
    procedure LoadTree;
    procedure OpenFile(const path: AnsiString);
    procedure SelectPath(const path: AnsiString);
    function SelectorChip: AnsiString;
    function ProjectLine: AnsiString;
    procedure ShowState;
    procedure StartDetect;
    procedure DetectNextPort;
    procedure FinishDetectPort;
    procedure StartBuild;
    procedure StartMonitor(const port: AnsiString);
    procedure StopChild;
    procedure ChildDone;
    procedure AutoFinish(rc: Integer);

    procedure OnOpen(Sender: TObject);
    procedure OnTreeChange(Sender: TObject);
    procedure OnChipChange(Sender: TObject);
    procedure OnDetect(Sender: TObject);
    procedure OnSave(Sender: TObject);
    procedure OnBuild(Sender: TObject);
    procedure OnMonitor(Sender: TObject);
    procedure OnStop(Sender: TObject);
    procedure OnTick(Sender: TObject);
    procedure OnFormResize(Sender: TControl; w, h: Integer);
  end;

var
  EspForm: TEspForm;

function StripCR(const s: AnsiString): AnsiString;
var i, n: Integer;
    r: AnsiString;
begin
  { presized, not appended per Char: a chunk can be 64 KB }
  SetLength(r, Length(s));
  n := 0;
  for i := 1 to Length(s) do
    if s[i] <> #13 then
    begin
      Inc(n);
      r[n] := s[i];
    end;
  SetLength(r, n);
  StripCR := r;
end;

function CountLines(const s: AnsiString): Integer;
var i, n: Integer;
begin
  n := 0;
  for i := 1 to Length(s) do
    if s[i] = #10 then Inc(n);
  CountLines := n;
end;

function Up(const dir: AnsiString): AnsiString;
var i: Integer;
begin
  i := Length(dir);
  while (i > 1) and (dir[i] = '/') do Dec(i);
  while (i > 1) and (dir[i] <> '/') do Dec(i);
  if i <= 1 then Up := '/' else Up := Copy(dir, 1, i - 1);
end;

{ The checkout (or unpacked release) we run from: the first folder above the
  executable that holds tools/esp_flash.sh, else the current directory. }
function FindRepoRoot: AnsiString;
var d: AnsiString;
    n: Integer;
begin
  d := ExtractFilePath(ExpandFileName(ParamStr(0)));
  n := 0;
  while (d <> '/') and (n < 8) do
  begin
    if FileExists(d + '/tools/esp_flash.sh') then
    begin
      if d[Length(d)] = '/' then d := Copy(d, 1, Length(d) - 1);
      FindRepoRoot := d;
      Exit;
    end;
    d := Up(d);
    Inc(n);
  end;
  FindRepoRoot := GetCurrentDir;
end;

procedure TEspForm.AddLog(const s: AnsiString);
begin
  LogText := LogText + StripCR(s);
  if Length(LogText) > LOG_CAP then
    LogText := Copy(LogText, Length(LogText) - LOG_CAP div 2, LOG_CAP);
  Log.Text := LogText;
  Log.CaretToLine(CountLines(LogText));
  if AutoRun then write(StripCR(s));
end;

procedure TEspForm.SetStatus(const s: AnsiString);
begin
  Status.Caption := s;
end;

procedure TEspForm.LoadTree;
var i, depth, j: Integer;
    p, name, pad: AnsiString;
begin
  Tree.Clear;
  TreePaths := EspListTree(RootDir, TREE_DEPTH);
  Tree.AddItem(ExtractFileName(RootDir) + '/');
  for i := 0 to Length(TreePaths) - 1 do
  begin
    p := TreePaths[i];
    depth := 0;
    for j := 1 to Length(p) - 1 do
      if p[j] = '/' then Inc(depth);
    name := p;
    if name[Length(name)] = '/' then name := Copy(name, 1, Length(name) - 1);
    name := ExtractFileName(name);
    if p[Length(p)] = '/' then name := name + '/';
    pad := '  ';
    for j := 1 to depth do pad := pad + '  ';
    Tree.AddItem(pad + name);
  end;
end;

procedure TEspForm.OpenFile(const path: AnsiString);
var b: TIdeBuffer;
begin
  b := TIdeBuffer.Create;
  if b.LoadFromFile(path) then
  begin
    CurFile := path;
    CurText := b.Text;
    Editor.Text := CurText;
  end
  else
    AddLog('cannot read ' + path + #10);
  b.Free;
end;

procedure TEspForm.SelectPath(const path: AnsiString);
begin
  Selected := path;
  CurProject := EspFindProjectRoot(path, RootDir);
  ShowState;
end;

function TEspForm.SelectorChip: AnsiString;
var t: AnsiString;
begin
  t := ChipBox.Text;
  if t = 'ESP32-S3' then SelectorChip := 'esp32s3'
  else if t = 'ESP32-C3' then SelectorChip := 'esp32c3'
  else if t = 'ESP32-S2' then SelectorChip := 'esp32s2'
  else SelectorChip := 'auto';
end;

function TEspForm.ProjectLine: AnsiString;
var pc: AnsiString;
begin
  if CurProject = '' then
  begin
    if Selected <> '' then
    begin
      if DirectoryExists(Selected) then
        ProjectLine := EspProjectProblem(Selected)
      else
        ProjectLine := EspProjectProblem(Up(Selected));
    end
    else
      ProjectLine := EspProjectProblem(RootDir);
    Exit;
  end;
  pc := EspProjectChip(CurProject);
  if pc = '' then
    ProjectLine := 'Project ' + ExtractFileName(CurProject) + ' (chip not stated: follows the board)'
  else
    ProjectLine := 'Project ' + ExtractFileName(CurProject) + ' builds for the ' + EspChipLabel(pc);
end;

procedure TEspForm.ShowState;
var s: AnsiString;
    i: Integer;
begin
  s := ProjectLine + '   |   ';
  if not Detected then
    s := s + 'Board: not detected yet (press Detect)'
  else if Length(Boards) = 0 then
    s := s + 'Board: none connected'
  else
    for i := 0 to Length(Boards) - 1 do
    begin
      if i > 0 then s := s + ', ';
      s := s + 'Board: ' + EspChipLabel(Boards[i].Chip) + ' on ' + Boards[i].Port;
    end;
  if Mode = mMonitor then s := s + '   |   monitoring ' + MonitorPort;
  SetStatus(s);
end;

{ ---- children: detect, build+flash, monitor ---- }

procedure TEspForm.StopChild;
begin
  if Proc.Running then StreamStop(Proc);
  Mode := mIdle;
end;

procedure TEspForm.StartDetect;
begin
  StopChild;             { a monitor holding the port would answer "busy" }
  SetLength(Boards, 0);
  Detected := False;
  DetectPorts := EspCandidatePorts;
  DetectIdx := 0;
  if Length(DetectPorts) = 0 then
  begin
    Detected := True;
    AddLog('Detect: no serial port (/dev/ttyACM*, /dev/ttyUSB*): no board is connected.' + #10);
    ShowState;
    if BuildAfterDetect then begin BuildAfterDetect := False; StartBuild; end;
    Exit;
  end;
  DetectNextPort;
end;

procedure TEspForm.DetectNextPort;
var port: AnsiString;
begin
  port := DetectPorts[DetectIdx];
  AddLog('Detect: asking ' + port + ' (esptool chip-id; this resets the board)' + #10);
  ProcOut := '';
  if StreamStart(Proc, '/bin/bash', ['-c',
       '. "${ESP_IDF_DIR:-$HOME/esp/esp-idf}/export.sh" >/dev/null 2>&1; ' +
       'exec esptool --port "$1" chip-id 2>&1', 'sh', port]) then
    Mode := mDetect
  else
  begin
    AddLog('Detect: could not start /bin/bash' + #10);
    Mode := mIdle;
  end;
end;

procedure TEspForm.FinishDetectPort;
var chip, why, port: AnsiString;
begin
  port := DetectPorts[DetectIdx];
  chip := EspChipFromEsptool(ProcOut);
  if chip <> '' then
  begin
    SetLength(Boards, Length(Boards) + 1);
    Boards[Length(Boards) - 1].Port := port;
    Boards[Length(Boards) - 1].Chip := chip;
    AddLog('Detect: ' + port + ' is an ' + EspChipLabel(chip) + #10);
  end
  else
  begin
    why := EspPortProblem(ProcOut);
    if why = '' then why := 'no ESP chip answered';
    AddLog('Detect: ' + port + ': ' + why + #10);
  end;
  Inc(DetectIdx);
  if DetectIdx < Length(DetectPorts) then
  begin
    DetectNextPort;
    Exit;
  end;
  Mode := mIdle;
  Detected := True;
  if Length(Boards) = 0 then
    AddLog('Detect: no board answered.' + #10);
  ShowState;
  if BuildAfterDetect then
  begin
    BuildAfterDetect := False;
    StartBuild;
  end;
end;

procedure TEspForm.StartBuild;
var sel, projChip, detChip, port, chip, why: AnsiString;
    i, nMatch: Integer;
begin
  if CurProject = '' then
  begin
    AddLog(ProjectLine + #10);
    SetStatus(ProjectLine);
    if AutoRun then AutoFinish(2);
    Exit;
  end;
  sel := SelectorChip;
  projChip := EspProjectChip(CurProject);
  if not Detected then
  begin
    { never guess a board: find out first, then come back here }
    BuildAfterDetect := True;
    StartDetect;
    Exit;
  end;
  { which board: the one chip asked for (the selector, else the project's),
    or the only one connected }
  detChip := '';
  port := '';
  nMatch := 0;
  for i := 0 to Length(Boards) - 1 do
    if ((sel <> 'auto') and (Boards[i].Chip = sel)) or
       ((sel = 'auto') and (projChip <> '') and (Boards[i].Chip = projChip)) then
    begin
      Inc(nMatch);
      if nMatch = 1 then begin detChip := Boards[i].Chip; port := Boards[i].Port; end;
    end;
  if (nMatch = 0) and (Length(Boards) = 1) then
  begin
    detChip := Boards[0].Chip;
    port := Boards[0].Port;
  end
  else if (nMatch = 0) and (Length(Boards) > 1) then
  begin
    why := 'Several boards are connected and none is the chip asked for: pick the chip.';
    AddLog(why + #10); SetStatus(why);
    if AutoRun then AutoFinish(2);
    Exit;
  end
  else if nMatch > 1 then
  begin
    why := 'Two boards of the same chip are connected: unplug one.';
    AddLog(why + #10); SetStatus(why);
    if AutoRun then AutoFinish(2);
    Exit;
  end;
  if not EspDecideChip(sel, detChip, projChip, chip, why) then
  begin
    AddLog(why + #10); SetStatus(why);
    if AutoRun then AutoFinish(2);
    Exit;
  end;
  if port = '' then
  begin
    why := 'No board detected: connect an ' + EspChipLabel(chip) + ' and press Detect.';
    AddLog(why + #10); SetStatus(why);
    if AutoRun then AutoFinish(2);
    Exit;
  end;
  if (CurFile <> '') and (Editor.Text <> CurText) then OnSave(nil);
  StopChild;           { the monitor must let go of the port before esptool }
  AddLog('Build+Flash: ' + ExtractFileName(CurProject) + ' for the ' +
         EspChipLabel(chip) + ' on ' + port + #10);
  ProcOut := '';
  MonitorPort := port;
  if StreamStart(Proc, '/bin/bash', ['-c',
       'cd "$1" || exit 2; ' +
       'exec tools/esp_flash.sh --project "$2" --chip "$3" --port "$4" ' +
       '--no-verify --seconds 4 2>&1', 'sh', RepoRoot, CurProject, chip, port]) then
    Mode := mBuild
  else
  begin
    AddLog('Build+Flash: could not start /bin/bash' + #10);
    if AutoRun then AutoFinish(2);
  end;
end;

procedure TEspForm.StartMonitor(const port: AnsiString);
begin
  StopChild;
  MonitorPort := port;
  AddLog('--- serial ' + port + ' (115200) ---' + #10);
  if StreamStart(Proc, '/bin/bash', ['-c',
       'stty -F "$1" 115200 cs8 -cstopb -parenb -echo raw || exit 2; exec cat "$1"',
       'sh', port]) then
    Mode := mMonitor
  else
    AddLog('Monitor: could not start /bin/bash' + #10);
  ShowState;
end;

procedure TEspForm.ChildDone;
var flashed: Boolean;
    m: TMode;
begin
  m := Mode;
  Mode := mIdle;
  case m of
    mDetect: FinishDetectPort;
    mBuild:
      begin
        { esp_flash exits nonzero both when nothing was written and when the
          board merely said nothing in its short read; only the first is a
          failed flash. }
        flashed := (Pos('esp_flash: writing flash...', ProcOut) > 0) and
                   (Pos('could not write', ProcOut) = 0) and
                   (Pos('nothing was written', ProcOut) = 0);
        if Proc.ExitCode = 0 then
          AddLog('Build+Flash: done, the board is running it.' + #10)
        else if flashed then
          AddLog('Build+Flash: flashed; the board was quiet in the first 4 seconds.' + #10)
        else
          AddLog('Build+Flash: FAILED (exit ' + IntToStr(Proc.ExitCode) +
                 '); see the log above.' + #10);
        if flashed then StartMonitor(MonitorPort)
        else if AutoRun then AutoFinish(1);
      end;
    mMonitor:
      begin
        AddLog(#10 + '--- serial ' + MonitorPort + ' closed (exit ' +
               IntToStr(Proc.ExitCode) + ') ---' + #10);
        if AutoRun then AutoFinish(0);
      end;
  end;
  ShowState;
end;

procedure TEspForm.AutoFinish(rc: Integer);
begin
  AutoRc := rc;
  AutoDone := True;
  StopChild;
  writeln;
  writeln('ESPIDE-AUTO-COMPLETE rc=', rc);
  if InLoop then gtk_main_quit;
end;

procedure TEspForm.OnTick(Sender: TObject);
var s: AnsiString;
begin
  if Proc.Running then
  begin
    s := StreamPoll(Proc, 0);
    if s <> '' then
    begin
      ProcOut := ProcOut + s;
      AddLog(s);
    end;
    if not Proc.Running then ChildDone;
  end;
  if AutoRun and (Mode = mMonitor) then
  begin
    Inc(AutoTicks);
    if AutoTicks * TICK_MS >= AutoSecs * 1000 then
    begin
      AddLog(#10 + '--- monitor stopped after ' + IntToStr(AutoSecs) + ' s ---' + #10);
      AutoFinish(0);
    end;
  end;
end;

{ ---- toolbar ---- }

procedure TEspForm.OnOpen(Sender: TObject);
var d: AnsiString;
begin
  d := Trim(RootEdit.Text);
  if (d <> '') and (d[1] <> '/') then d := RepoRoot + '/' + d;
  while (Length(d) > 1) and (d[Length(d)] = '/') do d := Copy(d, 1, Length(d) - 1);
  if not DirectoryExists(d) then
  begin
    SetStatus(d + ' is not a folder.');
    Exit;
  end;
  RootDir := d;
  CurFile := '';
  CurText := '';
  Editor.Text := '';
  LoadTree;
  SelectPath(RootDir);
end;

procedure TEspForm.OnTreeChange(Sender: TObject);
var i: Integer;
    p: AnsiString;
begin
  i := Tree.ItemIndex;
  if i < 0 then Exit;
  if i = 0 then begin SelectPath(RootDir); Exit; end;
  if i - 1 >= Length(TreePaths) then Exit;
  p := RootDir + '/' + TreePaths[i - 1];
  if p[Length(p)] = '/' then
    SelectPath(Copy(p, 1, Length(p) - 1))
  else
  begin
    OpenFile(p);
    SelectPath(p);
  end;
end;

procedure TEspForm.OnChipChange(Sender: TObject);
begin
  ShowState;
end;

procedure TEspForm.OnDetect(Sender: TObject);
begin
  if Mode in [mDetect, mBuild] then Exit;
  BuildAfterDetect := False;
  StartDetect;
end;

procedure TEspForm.OnSave(Sender: TObject);
begin
  if CurFile = '' then Exit;
  if WriteAllText(CurFile, Editor.Text) then
  begin
    CurText := Editor.Text;
    AddLog('saved ' + CurFile + #10);
  end
  else
    AddLog('could not save ' + CurFile + #10);
end;

procedure TEspForm.OnBuild(Sender: TObject);
begin
  if Mode in [mDetect, mBuild] then Exit;
  StartBuild;
end;

procedure TEspForm.OnMonitor(Sender: TObject);
var port: AnsiString;
begin
  if Mode in [mDetect, mBuild] then Exit;
  port := MonitorPort;
  if (port = '') and (Length(Boards) = 1) then port := Boards[0].Port;
  if port = '' then
  begin
    SetStatus('No board to monitor: press Detect first.');
    Exit;
  end;
  StartMonitor(port);
end;

procedure TEspForm.OnStop(Sender: TObject);
begin
  if Proc.Running then
  begin
    AddLog(#10 + '--- stopped ---' + #10);
    BuildAfterDetect := False;
    StopChild;
  end;
  ShowState;
end;

procedure TEspForm.OnFormResize(Sender: TControl; w, h: Integer);
begin
  if w = lastW then Exit;
  lastW := w;
  Split.SetBounds(0, BAR_H, w, h - BAR_H);
  Status.SetBounds(8, 36, w - 16, 22);
  if (not panedSeeded) and (w > 0) then
  begin
    Split.Position := W_TREE;
    RightSplit.Position := h - BAR_H - H_LOG;
    panedSeeded := True;
  end;
end;

function GuiAutoQuit(data: Pointer): Integer; cdecl;
begin
  gtk_main_quit;
  GuiAutoQuit := 0;
end;

function MkButton(const cap: AnsiString; x, w: Integer): TButton;
var b: TButton;
begin
  b := TButton.Create(nil);
  b.Caption := cap;
  b.Parent := EspForm;
  b.SetBounds(x, 4, w, 28);
  MkButton := b;
end;

var
  arg, start: AnsiString;
  f: TEspForm;

begin
  Application := TApplication.Create;
  Application.Initialize;

  EspForm := TEspForm.Create(nil);
  f := EspForm;
  f.Caption := 'PXX ESP32 IDE';
  f.SetBounds(0, 0, W_WIN, H_WIN);
  f.RepoRoot := FindRepoRoot;
  f.Mode := mIdle;
  f.Proc.Running := False;

  arg := '';
  start := f.RepoRoot + '/examples/esp32';
  if ParamCount >= 1 then arg := ParamStr(1);
  if arg = '--auto' then
  begin
    f.AutoRun := True;
    f.AutoSecs := 10;
    if ParamCount >= 2 then start := ParamStr(2);
    if ParamCount >= 3 then f.AutoSecs := StrToIntDef(ParamStr(3), 10);
  end
  else if (arg <> '') and (arg <> '--gui-smoke') then
    start := arg;

  f.RootEdit := TEdit.Create(nil);
  f.RootEdit.Parent := f;
  f.RootEdit.SetBounds(8, 4, 280, 28);
  f.OpenBtn := MkButton('Open', 292, 60);
  f.ChipLbl := TLabel.Create(nil);
  f.ChipLbl.Caption := 'Chip:';
  f.ChipLbl.Parent := f;
  f.ChipLbl.SetBounds(368, 9, 40, 20);
  f.ChipBox := TComboBox.Create(nil);
  f.ChipBox.Parent := f;
  f.ChipBox.SetBounds(410, 4, 120, 28);
  f.ChipBox.AddItem('auto');
  f.ChipBox.AddItem('ESP32-S3');
  f.ChipBox.AddItem('ESP32-C3');
  f.ChipBox.AddItem('ESP32-S2');
  f.DetectBtn := MkButton('Detect', 536, 70);
  f.SaveBtn := MkButton('Save', 620, 60);
  f.BuildBtn := MkButton('Build+Flash', 686, 100);
  f.MonBtn := MkButton('Monitor', 792, 76);
  f.StopBtn := MkButton('Stop', 874, 60);
  f.Status := TLabel.Create(nil);
  f.Status.Parent := f;
  f.Status.SetBounds(8, 36, W_WIN - 16, 22);

  f.Split := TPaned.Create(nil);
  f.Split.Parent := f;
  f.Split.SetBounds(0, BAR_H, W_WIN, H_WIN - BAR_H);
  f.Tree := TListBox.Create(nil);
  f.Tree.Parent := f.Split;
  f.RightSplit := TPaned.Create(nil);
  f.RightSplit.Vertical := True;
  f.RightSplit.Parent := f.Split;
  f.Editor := TMemo.Create(nil);
  f.Editor.Parent := f.RightSplit;
  f.Log := TMemo.Create(nil);
  f.Log.Parent := f.RightSplit;
  f.Split.Position := W_TREE;
  f.RightSplit.Position := H_WIN - BAR_H - H_LOG;

  f.Ticker := TTimer.Create(nil);
  f.Ticker.Interval := TICK_MS;

  f.OpenBtn.OnClick := @EspForm.OnOpen;
  f.Tree.OnChange := @EspForm.OnTreeChange;
  f.ChipBox.OnChange := @EspForm.OnChipChange;
  f.DetectBtn.OnClick := @EspForm.OnDetect;
  f.SaveBtn.OnClick := @EspForm.OnSave;
  f.BuildBtn.OnClick := @EspForm.OnBuild;
  f.MonBtn.OnClick := @EspForm.OnMonitor;
  f.StopBtn.OnClick := @EspForm.OnStop;
  f.Ticker.OnTimer := @EspForm.OnTick;
  f.OnResize := @EspForm.OnFormResize;

  if (start <> '') and (start[1] <> '/') then start := f.RepoRoot + '/' + start;
  f.RootEdit.Text := start;
  f.OnOpen(nil);
  f.ChipBox.ItemIndex := 0;
  f.Ticker.Enabled := True;

  Application.MainForm := f;
  if arg = '--gui-smoke' then
  begin
    g_timeout_add(400, @GuiAutoQuit, nil);
    Application.Run;
    if Pos('Project', f.Status.Caption) + Pos('ESP-IDF', f.Status.Caption) = 0 then
    begin
      writeln('GUI SMOKE FAIL: status line empty: ', f.Status.Caption);
      Halt(1);
    end;
    writeln('GUI SMOKE OK');
  end
  else if f.AutoRun then
  begin
    writeln('espide --auto: ', f.CurProject, ' | ', f.Status.Caption);
    f.StartBuild;
    f.InLoop := True;
    if not f.AutoDone then Application.Run;
    Halt(f.AutoRc);
  end
  else
    Application.Run;
end.
