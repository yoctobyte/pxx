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
    espide --gui-monitor-smoke --port <dev> <folder> <secs>
                                    press Monitor, hold it <secs>, press Stop,
                                    and assert control came back: the GUI half
                                    of the hardware check, which --gui-smoke
                                    cannot do because it starts no child
    espide --gui-libs-smoke <folder> open Settings > Libraries, check it is
                                    populated, close it, check it let go
    espide --auto <project> [secs]  detect, build+flash, monitor secs (10),
                                    print the log to stdout, exit 0 on a
                                    flashed board: the hardware check. }

uses gtk3_c, gtk3, controls, stdctrls, extctrls, comctrls, forms, menus, dialogs,
     uwidgetset, sysutils,
     buffer, runner, project, espproj;

const
  W_WIN    = 1100;
  H_WIN    = 720;
  BAR_H    = 64;        { the header's rough height: only used to seed the
                          log pane's opening split, since the toolbar and the
                          status line are real widgets in a box now }
  W_TREE   = 260;
  H_LOG    = 260;
  TICK_MS  = 100;
  LOG_FLUSH_MS = 250;   { pane refresh rate; see AddLog }
  LOG_CAP  = 32000;     { the pane keeps a TAIL: setting a GtkTextView to the
                          whole of a 150 KB IDF build log on every chunk cost
                          more than the chunks arrived, so the window fell
                          minutes behind its own child (measured on the S3) }
  TREE_DEPTH = 6;

type
  TMode = (mIdle, mDetect, mBuild, mMonitor);

  TEspForm = class(TForm)
  public
    RootEdit: TEdit;
    OpenBtn: TButton;
    ChipLbl: TLabel;
    ChipBox: TComboBox;
    { A PORT selector beside the chip one, and it is the safety-relevant control:
      a chip name has to be mapped to a board, and the only way to do that by
      asking is to reset boards. A port IS the answer. }
    PortLbl: TLabel;
    PortBox: TComboBox;
    DetectBtn, SaveBtn, BuildBtn, MonBtn, StopBtn: TButton;
    Status: TLabel;
    BoardBar: TLabel;    { the attached boards, on their own line }
    MainMenu: TMainMenu;
    Bar: TToolBar;
    HeadBox: TBox;
    Split, RightSplit: TPaned;
    Tree: TTreeView;
    Editor: TMemo;
    Log: TMemo;
    Ticker: TTimer;

    RepoRoot: AnsiString;
    RootDir: AnsiString;
    CurFile: AnsiString;       { absolute path of the file in the editor }
    CurText: AnsiString;       { its text as loaded or last saved }
    CurProject: AnsiString;    { project the selection belongs to, or '' }
    Selected: AnsiString;      { the selected tree entry, absolute }
    { espproj's record, not a local two-field one: it carries the by-id name
      and the USB bridge, which the listing fills in WITHOUT opening the port,
      and Chip/Mac/Revision, which only Detect can fill because asking resets
      the board. }
    Boards: TEspBoardArr;
    Detected: Boolean;         { Detect has run since the last change }
    Idf: TEspIdf;              { where ESP-IDF is; read from files, once }
    Dialout: TEspDialout;
    UseSg: Boolean;            { run serial commands through `sg dialout -c` }
    LibCfg: TEspLibCfg;        { the open project's extra libraries }
    { The Settings > Libraries editor. A SECOND TForm, rebuilt on every open
      rather than kept and re-shown: GTK's default delete-event destroys a
      window, so a kept form whose title bar was closed would hand its stale
      handle to the next Show. Rebuilding costs nothing and cannot dangle --
      the old form's buttons are gone with its widgets, so its handlers can
      never fire again. }
    LibDlg: TForm;
    LibUnits, LibComps, LibReqs: TMemo;

    Mode: TMode;
    Proc: TStreamProc;
    ProcOut: AnsiString;
    DetectPort: AnsiString;    { the ONE port Detect chose; never a list }
    AutoPort: AnsiString;      { --port on the command line, for --auto }
    BuildAfterDetect: Boolean;
    MonitorPort: AnsiString;
    LogText: AnsiString;

    AutoRun: Boolean;
    AutoSecs: Integer;
    AutoTicks: Integer;
    AutoMonT0: Int64;      { GetTickCount64 when the monitor opened }
    LogDirty: Boolean;     { pane is behind LogText }
    LogFlushT0: Int64;
    AutoRc: Integer;
    AutoDone: Boolean;
    InLoop: Boolean;       { Application.Run has started: quitting is legal }
    lastW: Integer;
    panedSeeded: Boolean;

    procedure AddLog(const s: AnsiString);
    procedure FlushLog;
    procedure SetStatus(const s: AnsiString);
    procedure LoadTree;
    procedure OpenFile(const path: AnsiString);
    procedure SelectPath(const path: AnsiString);
    function SelectorChip: AnsiString;
    function SelectorPort: AnsiString;
    function DetectChipHint: AnsiString;
    procedure RefillPortBox;
    function ProjectLine: AnsiString;
    procedure ShowState;
    procedure RelistBoards;
    procedure StartDetect;
    procedure DetectOnePort;
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
    procedure OnMenuOpenFolder(Sender: TObject);
    procedure OnMenuOpenFile(Sender: TObject);
    procedure OnMenuQuit(Sender: TObject);
    procedure OnMenuAbout(Sender: TObject);
    procedure OnMenuLibraries(Sender: TObject);
    procedure OnMenuIdf(Sender: TObject);
    procedure OnLibSave(Sender: TObject);
    procedure OnLibClose(Sender: TObject);
    procedure BuildMenu;
  end;

var
  EspForm: TEspForm;

{ One shell word list, space separated. The parts are paths and component
  names the user typed, so a space inside one would split it -- the whole
  string is single-quoted by EspShellQuote at the call site, which keeps it
  one argument to `export` but not one word to the build.sh that re-splits
  it. Documented rather than solved: a path with a space in it is not a
  shape the IDF build tolerates either. }
function JoinSpace(const a: TStrArray): AnsiString;
var i: Integer;
    r: AnsiString;
begin
  r := '';
  for i := 0 to Length(a) - 1 do
  begin
    if i > 0 then r := r + ' ';
    r := r + a[i];
  end;
  JoinSpace := r;
end;

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

{ Push the accumulated text into the pane. THE EXPENSIVE HALF: setting a
  GtkTextView's text re-lays out the whole buffer and CaretToLine scrolls it, so
  this is O(LOG_CAP) and must not run once per arriving chunk. }
procedure TEspForm.FlushLog;
begin
  if not LogDirty then Exit;
  LogDirty := False;
  LogFlushT0 := GetTickCount64;
  Log.Text := LogText;
  Log.CaretToLine(CountLines(LogText));
end;

{ A serial monitor delivers up to 16 x 4096 = 64 KB per tick (StreamPoll's drain
  cap), and this used to do the full pane rewrite plus a CountLines over the whole
  tail FOR EVERY CHUNK. That is more work than a 100 ms tick has, so on a board
  that streams -- one reboot-looping under cat's DTR/RTS, say -- the IDE never
  catches up and wedges for as long as the board talks. Measured: 47 minutes on a
  monitor asked for 6 seconds, log frozen, nothing deadlocked.

  Two changes. The pane is now updated at most every LOG_FLUSH_MS, and stdout is
  written FIRST: it used to come last, behind the GTK work, so when the pane fell
  behind, the log file froze too and a live run was indistinguishable from a dead
  one. The record a headless run leaves must not queue behind a widget. }
procedure TEspForm.AddLog(const s: AnsiString);
var t: AnsiString;
begin
  t := StripCR(s);
  if AutoRun then
  begin
    write(t);            { RAW (bar CR): the log is a capture, not a rendering }
    Flush(Output);
  end;
  LogText := LogText + SanitizeUtf8ForText(t);
  if Length(LogText) > LOG_CAP then
    LogText := Copy(LogText, Length(LogText) - LOG_CAP div 2, LOG_CAP);
  LogDirty := True;
  if GetTickCount64 - LogFlushT0 >= LOG_FLUSH_MS then FlushLog;
end;

procedure TEspForm.SetStatus(const s: AnsiString);
begin
  Status.Caption := s;
end;

{ One level of the tree under `node`, recursing into sub-directories.
  File-level and not a method, because the pinned compiler has no nested
  routines and a method would have to carry the depth anyway. }
procedure FillTreeNode(node: TTreeNode; const dir: AnsiString; depth: Integer);
var ents: TStrArray;
    i: Integer;
    e, full: AnsiString;
    child: TTreeNode;
begin
  ents := EspListDir(dir);
  for i := 0 to Length(ents) - 1 do
  begin
    e := ents[i];
    if e[Length(e)] = '/' then
    begin
      full := dir + '/' + Copy(e, 1, Length(e) - 1);
      child := node.AddChild(e, full);
      if depth < TREE_DEPTH then FillTreeNode(child, full, depth + 1);
    end
    else
      node.AddChild(e, dir + '/' + e);
  end;
end;

procedure TEspForm.LoadTree;
var root: TTreeNode;
begin
  Tree.Clear;
  root := Tree.AddRoot(ExtractFileName(RootDir) + '/', RootDir);
  FillTreeNode(root, RootDir, 0);
  { COLLAPSED by default -- the whole point of issue 4 -- except for the root
    itself, so the window is not one closed line when it opens. Expand is
    called after the children exist: GTK refuses to open a row with none. }
  root.Expand(False);
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
  { the extra-libraries config travels WITH the project, so it is re-read
    whenever the project changes rather than held from startup }
  if CurProject <> '' then LibCfg := EspLibCfgLoad(CurProject)
  else LibCfg := EspLibCfgParse('');
  ShowState;
end;

{ The first line of a multi-line explanation. A refusal from EspChooseDetectPort
  carries the port list on following lines: the log wants all of it, the one-line
  status bar wants the sentence and would otherwise show a menu squeezed into a
  label. }
function FirstLineOf(const s: AnsiString): AnsiString;
var p: Integer;
begin
  p := Pos(#10, s);
  if p > 0 then FirstLineOf := Copy(s, 1, p - 1) else FirstLineOf := s;
end;

function TEspForm.SelectorChip: AnsiString;
var t: AnsiString;
begin
  t := ChipBox.Text;
  if t = 'ESP32-S3' then SelectorChip := 'esp32s3'
  else if t = 'ESP32-C3' then SelectorChip := 'esp32c3'
  else if t = 'ESP32-S2' then SelectorChip := 'esp32s2'
  { the CLASSIC part. Last of the named arms because its label is a PREFIX of
    the others' -- if this compared with Pos or a prefix test it would swallow
    them, and as an equality test the order is merely documentation. }
  else if t = 'ESP32' then SelectorChip := 'esp32'
  else SelectorChip := 'auto';
end;

{ The chosen port, or '' for 'auto'. A command-line --port wins, so a headless
  --auto run can name its own board and touch nothing else. The box holds by-id
  names; the full path is looked up from the listing so a name the user is
  reading is never string-built into a device path. }
function TEspForm.SelectorPort: AnsiString;
var t: AnsiString;
    i: Integer;
begin
  SelectorPort := '';
  if AutoPort <> '' then begin SelectorPort := AutoPort; Exit; end;
  if PortBox = nil then Exit;
  t := PortBox.Text;
  if (t = '') or (t = 'auto') then Exit;
  for i := 0 to Length(Boards) - 1 do
    if (Boards[i].Name = t) or (Boards[i].Port = t) then
    begin
      SelectorPort := Boards[i].Port;
      Exit;
    end;
  { not attached any more: hand it back as typed so EspChooseDetectPort can say
    so by name, rather than silently falling back to 'auto' and probing }
  SelectorPort := t;
end;

{ Which chip to narrow the port choice BY: the selector when it names one, else
  what the project builds for. Not the detected chip -- that is what we are
  trying to find out, and using it here would be circular. }
function TEspForm.DetectChipHint: AnsiString;
var s: AnsiString;
begin
  s := SelectorChip;
  if (s <> '') and (s <> 'auto') then begin DetectChipHint := s; Exit; end;
  DetectChipHint := EspProjectChip(CurProject);
end;

{ The port box holds 'auto' plus the by-id name of every attached board. Built
  from the listing, which opens nothing. }
procedure TEspForm.RefillPortBox;
var i: Integer;
    keep: AnsiString;
begin
  if PortBox = nil then Exit;
  keep := PortBox.Text;
  PortBox.Clear;
  PortBox.AddItem('auto');
  for i := 0 to Length(Boards) - 1 do PortBox.AddItem(Boards[i].Name);
  PortBox.Text := 'auto';
  { keep an explicit choice across a relist, so a user who picked their own board
    does not silently return to 'auto' -- which is the setting that can refuse,
    or on a single-board host probe }
  if keep <> '' then
    for i := 0 to Length(Boards) - 1 do
      if Boards[i].Name = keep then PortBox.Text := keep;
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
var s, note: AnsiString;
    i: Integer;
begin
  s := ProjectLine + '   |   ' + EspIdfLine(Idf);
  if UseSg then s := s + '   |   serial via `sg dialout`';
  note := EspDialoutNote(Dialout);
  if (note <> '') and (not UseSg) then s := s + '   |   ' + note;
  if not EspLibCfgEmpty(LibCfg) then s := s + '   |   ' + EspLibCfgLine(LibCfg);
  if Mode = mMonitor then s := s + '   |   monitoring ' + MonitorPort;
  SetStatus(s);

  { THE BOARDS GET THEIR OWN LINE, and that is a measurement and not taste:
    three attached boards render as ~200 characters of by-id name, which on
    one line with the project and the IDF version ellipsized everything after
    the first board away. The full text also goes to the LOG whenever the
    list changes, because even one line ellipsizes on a narrow window and the
    log is the place text can be long. }
  s := '';
  if Length(Boards) = 0 then
    s := 'No board attached'
  else
    for i := 0 to Length(Boards) - 1 do
    begin
      if i > 0 then s := s + '   +   ';
      s := s + EspBoardLine(Boards[i]);
    end;
  { THE LIST IS ALWAYS SHOWN, DETECTED OR NOT, and that is the point of issue
    5: RelistBoards reads /dev/serial/by-id names only, so the port, the
    identity and the USB bridge are on screen without anything having been
    opened. Opening a port RESETS the board -- interrupting whatever it is
    running -- so only Detect does that, and only Detect can fill in the
    chip, the MAC and the revision. }
  if (Length(Boards) > 0) and (not Detected) then
    s := s + '      (Detect asks the chip -- it resets the board)';
  BoardBar.Caption := s;
end;

{ Re-read the attached boards. OPENS NOTHING: by-id names and the bridge they
  encode, which is udev's own rendering of the USB descriptors. Any chip/MAC
  a previous Detect learned is dropped with the old list, because a replug can
  put a different board on the same name. }
procedure TEspForm.RelistBoards;
var i: Integer;
begin
  Boards := EspListBoards;
  if Length(Boards) = 0 then
  begin
    { no /dev/serial/by-id (no udev, or a container): fall back to the raw
      device names, which still open nothing }
    Boards := EspBoardsFromPorts(EspCandidatePorts);
  end;
  Detected := False;
  if Length(Boards) = 0 then
    AddLog('Boards: none attached.' + #10)
  else
    for i := 0 to Length(Boards) - 1 do
      AddLog('Board: ' + EspBoardLine(Boards[i]) + #10);
  RefillPortBox;
end;

{ ---- children: detect, build+flash, monitor ---- }

procedure TEspForm.StopChild;
begin
  if Proc.Running then StreamStop(Proc);
  Mode := mIdle;
end;

{ ONE port, chosen before anything is opened, or a refusal.

  This used to walk every attached port: `Inc(DetectIdx); if DetectIdx <
  Length(Boards) then DetectNextPort`. On a host with three boards that reset two
  belonging to other people, in one press, while logging "this resets the board"
  each time. A probe must touch exactly what the user pointed at, and when that
  cannot be determined from the listing alone the answer is to ask the user --
  not to find out by resetting hardware to see what it is.

  The rule lives in EspChooseDetectPort so it can be tested against a fixture
  directory of three ports without a board or a display. }
procedure TEspForm.StartDetect;
var port, why: AnsiString;
begin
  StopChild;             { a monitor holding the port would answer "busy" }
  RelistBoards;
  if not EspChooseDetectPort(Boards, SelectorPort, DetectChipHint, port, why) then
  begin
    Detected := True;    { asked and answered: the refusal IS the outcome }
    AddLog('Detect: ' + why + #10);
    SetStatus('Detect: ' + FirstLineOf(why));
    ShowState;
    { a refusal must NOT fall through into a build that then picks a port
      itself -- that would defeat the whole point of refusing }
    if BuildAfterDetect then
    begin
      BuildAfterDetect := False;
      AddLog('Build+Flash: stopped, because Detect could not tell which board to ask.' + #10);
    end;
    { and a headless --auto run must END on a refusal rather than sit there: the
      first spy run of this fix exited 124, killed by its own timeout, because a
      refusal reached no AutoFinish. A batch caller cannot tell that apart from a
      hang, and "the harness timed out" is not a verdict. }
    if AutoRun then AutoFinish(2);
    Exit;
  end;
  DetectPort := port;
  ShowState;
  DetectOnePort;
end;

procedure TEspForm.DetectOnePort;
var port, cmd: AnsiString;
begin
  port := DetectPort;
  AddLog('Detect: asking ' + port + ' (esptool chip-id; this resets THIS board' +
         ' and no other)' + #10);
  ProcOut := '';
  { The port is QUOTED INTO the command rather than passed as $1, because
    `sg dialout -c` takes one string and forwards no arguments. Quoting is
    EspShellQuote's job whether or not sg is in the way, so there is one
    command shape and not two. }
  cmd := EspWrapSg('. "${ESP_IDF_DIR:-$HOME/esp/esp-idf}/export.sh" >/dev/null 2>&1; ' +
                   'exec esptool --port ' + EspShellQuote(port) + ' chip-id 2>&1', UseSg);
  if StreamStart(Proc, '/bin/bash', ['-c', cmd, 'sh']) then
    Mode := mDetect
  else
  begin
    AddLog('Detect: could not start /bin/bash' + #10);
    Mode := mIdle;
  end;
end;

procedure TEspForm.FinishDetectPort;
var chip, why: AnsiString;
    i, answered: Integer;
begin
  answered := -1;
  for i := 0 to Length(Boards) - 1 do
    if Boards[i].Port = DetectPort then answered := i;
  chip := EspChipFromEsptool(ProcOut);
  if (chip <> '') and (answered >= 0) then
  begin
    { fill the record IN PLACE -- the listing already knows this board's by-id
      name and bridge, and rebuilding it here would throw that away }
    Boards[answered].Chip := chip;
    Boards[answered].Mac := EspMacFromEsptool(ProcOut);
    Boards[answered].Revision := EspRevisionFromEsptool(ProcOut);
    AddLog('Detect: ' + EspBoardLine(Boards[answered]) + #10);
  end
  else
  begin
    why := EspPortProblem(ProcOut);
    if why = '' then why := 'no ESP chip answered (it was still reset by the attempt)';
    AddLog('Detect: ' + DetectPort + ': ' + why + #10);
  end;
  { NO loop. One port was chosen, one port was asked, and that is the end of it.
    The `Inc(DetectIdx); if DetectIdx < Length(Boards) then DetectNextPort` that
    stood here is what reset other people's boards. }
  Mode := mIdle;
  Detected := True;
  ShowState;
  if BuildAfterDetect then
  begin
    BuildAfterDetect := False;
    StartBuild;
  end;
end;

procedure TEspForm.StartBuild;
var sel, projChip, detChip, port, chip, why: AnsiString;
    libFlags, libComps, libReqs: AnsiString;
    i, nMatch, nAnswered, onlyAnswered: Integer;
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
  { ONLY BOARDS THAT ANSWERED. Boards now holds every attached port, detected
    or not, because the listing fills it without opening anything -- so an
    undetected row has Chip = '' and must not be matched, and must not be
    counted as "the only one connected" either. }
  nAnswered := 0;
  onlyAnswered := -1;
  for i := 0 to Length(Boards) - 1 do
    if Boards[i].Chip <> '' then
    begin
      nAnswered := nAnswered + 1;
      if nAnswered = 1 then onlyAnswered := i;
    end;
  for i := 0 to Length(Boards) - 1 do
    if (Boards[i].Chip <> '') and
       (((sel <> 'auto') and (Boards[i].Chip = sel)) or
        ((sel = 'auto') and (projChip <> '') and (Boards[i].Chip = projChip))) then
    begin
      Inc(nMatch);
      if nMatch = 1 then begin detChip := Boards[i].Chip; port := Boards[i].Port; end;
    end;
  if (nMatch = 0) and (nAnswered = 1) then
  begin
    detChip := Boards[onlyAnswered].Chip;
    port := Boards[onlyAnswered].Port;
  end
  else if (nMatch = 0) and (nAnswered > 1) then
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
  libFlags := JoinSpace(EspLibCfgPxxFlags(LibCfg));
  libComps := JoinSpace(LibCfg.ComponentDirs);
  libReqs := JoinSpace(LibCfg.Requires);
  if not EspLibCfgEmpty(LibCfg) then
    AddLog('Libraries: ' + EspLibCfgLine(LibCfg) + ' (from espide.cfg)' + #10);
  StopChild;           { the monitor must let go of the port before esptool }
  AddLog('Build+Flash: ' + ExtractFileName(CurProject) + ' for the ' +
         EspChipLabel(chip) + ' on ' + port + #10);
  ProcOut := '';
  MonitorPort := port;
  { THE PROJECT'S EXTRA LIBRARIES REACH THE BUILD AS ENVIRONMENT, because the
    build is delegated to the project's own build.sh -- espide holds no
    compiler flags and adding a --fu switch to esp_flash.sh would put them
    back in the IDE. A build.sh honours ESP_PXXFLAGS on its pxx line and
    ESP_EXTRA_COMPONENT_DIRS / ESP_REQUIRES on its idf.py line;
    examples/esp32/hello-esp32/build.sh is the worked example. A project that
    reads neither is unaffected, which is why this is safe to always set. }
  { AND IT GOES THROUGH `sg dialout` TOO, for the same reason Detect and
    Monitor do: flashing WRITES to the tty, so a login that predates the group
    grant fails here exactly as it fails there -- esp_flash.sh's own check
    answers `$PORT is not writable`. Detect and Monitor were wrapped and this
    was not, which would have given a host the confusing half-state of a board
    that identifies itself and then refuses to be flashed. Every value is
    EspShellQuote'd into the string rather than passed as $1..$4, because
    `sg dialout -c` takes one command string and forwards no arguments. }
  if StreamStart(Proc, '/bin/bash', ['-c',
       EspWrapSg('cd ' + EspShellQuote(RepoRoot) + ' || exit 2; ' +
       'export ESP_PXXFLAGS=' + EspShellQuote(libFlags) + '; ' +
       'export ESP_EXTRA_COMPONENT_DIRS=' + EspShellQuote(libComps) + '; ' +
       'export ESP_REQUIRES=' + EspShellQuote(libReqs) + '; ' +
       'exec tools/esp_flash.sh --project ' + EspShellQuote(CurProject) +
       ' --chip ' + EspShellQuote(chip) + ' --port ' + EspShellQuote(port) +
       ' --no-verify --seconds 4 2>&1', UseSg), 'sh']) then
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
  { The command, and the reason it is not built here, live in espproj:
    EspMonitorCmd carries the invariant that the reader must not splice into our
    pipe, and bochan guards it without a board or a display.
    bug-s-espide-auto-never-exits-after-build-flash }
  if StreamStart(Proc, '/bin/bash', ['-c', EspMonitorCmd(port, UseSg), 'sh']) then
  begin
    Mode := mMonitor;
    { the clock --auto's monitor window is measured against, started here rather
      than counted in ticks -- see OnTick }
    AutoMonT0 := GetTickCount64;
    AutoTicks := 0;
  end
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
  { the child is gone, so no later chunk will arrive to trigger a flush; do not
    leave the last lines of a finished run waiting on the next tick }
  FlushLog;
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
  { ELAPSED CLOCK TIME, not a count of ticks. `AutoTicks * TICK_MS` assumed every
    tick arrives on its 100 ms schedule, so it measured timer ticks and called
    them seconds. A monitor on a talkative port breaks that assumption: each tick
    drains up to 16 reads, the timer falls behind, and `--auto <n>` then runs
    longer than n seconds. Wall time cannot drift that way.

    This is a SECOND, independent defect from the wedge AddLog above describes,
    and not the cause of it -- I briefly believed it was, on the strength of one
    clean run, and the ticket records why that was wrong. Fixing only this one
    would have left the IDE wedging with a more honest clock. }
  { the pane still catches up when the child has gone quiet }
  if LogDirty and (GetTickCount64 - LogFlushT0 >= LOG_FLUSH_MS) then FlushLog;
  if AutoRun and (Mode = mMonitor) then
  begin
    Inc(AutoTicks);   { kept for the log line below: how many ticks that took }
    if GetTickCount64 - AutoMonT0 >= Int64(AutoSecs) * 1000 then
    begin
      AddLog(#10 + '--- monitor stopped after ' + IntToStr(AutoSecs) + ' s (' +
             IntToStr(AutoTicks) + ' ticks; ' +
             IntToStr(Integer(GetTickCount64 - AutoMonT0)) + ' ms elapsed) ---' + #10);
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
var n: TTreeNode;
    p: AnsiString;
begin
  n := Tree.Selected;
  if n = nil then Exit;
  p := n.Data;
  if p = '' then Exit;
  { a node whose caption ends in '/' is a directory: select it, do not try to
    read it into the editor }
  if n.Text[Length(n.Text)] = '/' then
    SelectPath(p)
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

{ ---- the main menu ---- }

procedure TEspForm.OnMenuOpenFolder(Sender: TObject);
var dlg: TSelectDirectoryDialog;
begin
  { one dialog for a folder AND for a project: a project IS a folder here (one
    with a CMakeLists.txt and a build.sh), and the status line already says
    which of the two you picked. Two menu entries that open the same chooser
    and then differ in whether they complain would be a worse answer than one
    that opens what you chose and tells you what it is. }
  dlg := TSelectDirectoryDialog.Create('Open a folder or an ESP-IDF project');
  { start where you already are, not in the process's CWD -- which for a
    launcher-started IDE is the repo root and for a desktop-started one is $HOME }
  dlg.InitialDir := RootDir;
  if dlg.Execute then
  begin
    RootEdit.Text := dlg.FileName;
    OnOpen(nil);
  end;
  dlg.Free;
end;

procedure TEspForm.OnMenuOpenFile(Sender: TObject);
var dlg: TOpenDialog;
begin
  dlg := TOpenDialog.Create('Open a source file');
  dlg.InitialDir := RootDir;
  dlg.Filter := 'Sources|*.pas;*.inc;*.c;*.h;*.py;*.npy|' +
                'Project files|CMakeLists.txt;*.cmake;sdkconfig*;*.sh|' +
                'All files|*';
  if dlg.Execute then
  begin
    OpenFile(dlg.FileName);
    { the tree is rooted elsewhere, so the file may be outside it -- SelectPath
      still finds its project root, which is what Build + Flash acts on }
    SelectPath(dlg.FileName);
  end;
  dlg.Free;
end;

procedure TEspForm.OnMenuQuit(Sender: TObject);
begin
  StopChild;
  gtk_main_quit;
end;

procedure TEspForm.OnMenuAbout(Sender: TObject);
var s: AnsiString;
    pin: TEspPin;
    idf: TEspIdf;
begin
  pin := EspPinInfo(RepoRoot);
  idf := EspDetectIdf;
  s := 'PXX ESP32 IDE' + #10 + #10 +
       EspPinLine(pin) + #10 +
       EspIdfLine(idf) + #10;
  if not idf.Found then s := s + idf.Advice + #10;
  s := s + EspDialoutNote(EspDialoutState);
  ShowMessage(s);
end;

{ One entry per line, blanks dropped. The editor is three memos rather than
  three one-line fields because a project can have several of each, and a
  line-per-entry text box is the cheapest editor that does not cap the count. }
function LinesOf(const t: AnsiString): TStrArray;
var a: TStrArray;
    i, start: Integer;
    ln: AnsiString;
begin
  SetLength(a, 0);
  start := 1;
  for i := 1 to Length(t) + 1 do
    if (i > Length(t)) or (t[i] = #10) then
    begin
      ln := Trim(Copy(t, start, i - start));
      if ln <> '' then
      begin
        SetLength(a, Length(a) + 1);
        a[Length(a) - 1] := ln;
      end;
      start := i + 1;
    end;
  LinesOf := a;
end;

function JoinLines(const a: TStrArray): AnsiString;
var i: Integer;
    s: AnsiString;
begin
  s := '';
  for i := 0 to Length(a) - 1 do
    s := s + a[i] + #10;
  JoinLines := s;
end;

procedure TEspForm.OnMenuIdf(Sender: TObject);
var s: AnsiString;
begin
  s := EspIdfLine(Idf);
  if Idf.Found then
  begin
    s := s + #10 + #10 + 'Path: ' + Idf.Path;
    if Idf.PyEnv <> '' then s := s + #10 + 'Python env: ' + Idf.PyEnv;
    if Idf.Version = '' then
      s := s + #10 + #10 +
           'The version header could not be read, so the version is unknown; ' +
           'the checkout is there and builds will use it.';
  end
  else
    s := s + #10 + #10 + Idf.Advice;
  ShowMessage(s);
end;

procedure TEspForm.OnLibSave(Sender: TObject);
var c: TEspLibCfg;
begin
  if CurProject = '' then Exit;
  c.UnitDirs := LinesOf(LibUnits.Text);
  c.ComponentDirs := LinesOf(LibComps.Text);
  c.Requires := LinesOf(LibReqs.Text);
  if EspLibCfgSave(CurProject, c) then
  begin
    LibCfg := c;
    AddLog('saved ' + EspLibCfgPath(CurProject) + #10);
    ShowState;
    OnLibClose(nil);
  end
  else
    AddLog('could not write ' + EspLibCfgPath(CurProject) + #10);
end;

procedure TEspForm.OnLibClose(Sender: TObject);
begin
  if LibDlg <> nil then
  begin
    WidgetSet.DestroyWidget(LibDlg.Handle);
    LibDlg := nil;
  end;
end;

procedure TEspForm.OnMenuLibraries(Sender: TObject);
var box, btns: TBox;
    lab: TLabel;
    b: TButton;
    c: TEspLibCfg;
    d: Integer;
begin
  if CurProject = '' then
  begin
    ShowMessage('No project is open. Select a folder that holds a CMakeLists.txt ' +
                'and a build.sh, then open Settings > Libraries again.');
    Exit;
  end;
  OnLibClose(nil);
  c := EspLibCfgLoad(CurProject);

  LibDlg := TForm.Create(nil);
  LibDlg.Caption := 'Libraries for ' + ExtractFileName(CurProject);
  LibDlg.SetBounds(0, 0, 560, 460);

  box := TBox.Create(nil);
  box.Vertical := True;
  box.Parent := LibDlg;

  lab := TLabel.Create(nil);
  lab.Caption := 'Extra unit search folders -- one per line. Each becomes a pxx -Fu.';
  lab.Parent := box;
  LibUnits := TMemo.Create(nil);
  LibUnits.Parent := box;
  LibUnits.Text := JoinLines(c.UnitDirs);

  lab := TLabel.Create(nil);
  { "OF components, not of projects" is a measured trap, not padding: IDF
    treats every subdirectory of an EXTRA_COMPONENT_DIRS entry as a component,
    so pointing it at a folder of IDF PROJECTS makes cmake read each project's
    CMakeLists as a component, and it dies inside __component_get_requirements
    with `define_property command is not scriptable` -- which names neither the
    folder nor the project and reads like a broken IDF install.

    TWO LINES in one label, not one long one: a label's minimum width is its
    whole longest line, so putting the caveat on the same line would have made
    this 113-character string the DIALOG's width floor -- the exact thing issue
    1 removed from the main window, reintroduced by a comment. }
  lab.Caption := 'Extra ESP-IDF component folders -- one per line (EXTRA_COMPONENT_DIRS).' +
                 #10 + 'A folder OF components, not of projects.';
  lab.Parent := box;
  LibComps := TMemo.Create(nil);
  LibComps.Parent := box;
  LibComps.Text := JoinLines(c.ComponentDirs);

  lab := TLabel.Create(nil);
  lab.Caption := 'ESP-IDF components this project REQUIREs -- one per line.';
  lab.Parent := box;
  LibReqs := TMemo.Create(nil);
  LibReqs.Parent := box;
  LibReqs.Text := JoinLines(c.Requires);

  lab := TLabel.Create(nil);
  lab.Caption := 'Saved in ' + EspLibCfgPath(CurProject) +
                 ', so it travels with the project.';
  lab.Ellipsize := True;
  lab.Parent := box;

  btns := TBox.Create(nil);
  { a row of buttons: each keeps its own size, or the last one is stretched
    across the window }
  btns.ExpandRest := False;
  btns.Spacing := 8;
  btns.Parent := box;
  b := TButton.Create(nil);
  b.Caption := 'Save';
  b.Parent := btns;
  b.OnClick := @EspForm.OnLibSave;
  b := TButton.Create(nil);
  b.Caption := 'Close';
  b.Parent := btns;
  b.OnClick := @EspForm.OnLibClose;

  { the box IS the window's content, same as the main form's splitter }
  LibDlg.SetClient(box, 0);
  d := LibDlg.Realize;
  LibDlg.Show;
end;

procedure TEspForm.BuildMenu;
var fileM, boardM, setM, helpM, it: TMenuItem;
begin
  MainMenu := TMainMenu.Create(nil);

  fileM := TMenuItem.Create(nil);
  fileM.Caption := '&File';
  MainMenu.Items.Add(fileM);
  it := TMenuItem.Create(nil);
  it.Caption := '&Open Folder or Project...';
  it.OnClick := @EspForm.OnMenuOpenFolder;
  fileM.Add(it);
  it := TMenuItem.Create(nil);
  it.Caption := 'Open &File...';
  it.OnClick := @EspForm.OnMenuOpenFile;
  fileM.Add(it);
  it := TMenuItem.Create(nil);
  it.Caption := '&Save';
  it.OnClick := @EspForm.OnSave;
  fileM.Add(it);
  it := TMenuItem.Create(nil);
  it.Caption := '-';
  fileM.Add(it);
  it := TMenuItem.Create(nil);
  it.Caption := '&Quit';
  it.OnClick := @EspForm.OnMenuQuit;
  fileM.Add(it);

  boardM := TMenuItem.Create(nil);
  boardM.Caption := '&Board';
  MainMenu.Items.Add(boardM);
  it := TMenuItem.Create(nil);
  it.Caption := '&Detect';
  it.OnClick := @EspForm.OnDetect;
  boardM.Add(it);
  it := TMenuItem.Create(nil);
  it.Caption := '&Build + Flash';
  it.OnClick := @EspForm.OnBuild;
  boardM.Add(it);
  it := TMenuItem.Create(nil);
  it.Caption := '&Monitor';
  it.OnClick := @EspForm.OnMonitor;
  boardM.Add(it);
  it := TMenuItem.Create(nil);
  it.Caption := '-';
  boardM.Add(it);
  it := TMenuItem.Create(nil);
  it.Caption := 'S&top';
  it.OnClick := @EspForm.OnStop;
  boardM.Add(it);

  setM := TMenuItem.Create(nil);
  setM.Caption := '&Settings';
  MainMenu.Items.Add(setM);
  it := TMenuItem.Create(nil);
  it.Caption := '&Libraries...';
  it.OnClick := @EspForm.OnMenuLibraries;
  setM.Add(it);
  it := TMenuItem.Create(nil);
  it.Caption := '&ESP-IDF';
  it.OnClick := @EspForm.OnMenuIdf;
  setM.Add(it);

  helpM := TMenuItem.Create(nil);
  helpM.Caption := '&Help';
  MainMenu.Items.Add(helpM);
  it := TMenuItem.Create(nil);
  it.Caption := '&About';
  it.OnClick := @EspForm.OnMenuAbout;
  helpM.Add(it);

  Self.Menu := MainMenu;
end;

procedure TEspForm.OnFormResize(Sender: TControl; w, h: Integer);
begin
  { THE PANES ARE NOT RESIZED HERE ANY MORE. Form.SetClient hands Split the
    window's content area, so GTK sizes it -- which is what makes the window
    freely resizable in BOTH directions and removes the reason this handler used
    to bail out on `w = lastW`. That guard was against a feedback loop of its
    own making: setting the pane's size grew the container's minimum, which fired
    this handler with a bigger allocation, which grew the pane again. It also
    meant a height-only drag re-laid out nothing.

    What is left here is the two things that genuinely live in the header strip:
    the status label's width (it is at absolute coordinates, like the toolbar),
    and seeding the splitter positions ONCE. GtkPaned clamps a position set
    before it has an allocation, so the seed has to wait for the first real one
    -- and must not be repeated, or every window resize would drag the splitters
    back to their starting places under the user's hands. }
  { THE STATUS LABEL IS NOT RESIZED HERE ANY MORE. It lives in the header box
    now, so GTK gives it the full width; setting one made the window's minimum
    width follow the label. lastW is kept because the seed below reads w. }
  if w <> lastW then lastW := w;
  { h IS THE HEADER STRIP'S HEIGHT NOW, NOT THE WINDOW'S. This handler is fired
    by the form's absolute-coordinate container, and SetClient pinned that to
    BAR_H -- so the log pane's opening height comes from the design constants and
    not from h, which would have silently seeded it at a few pixels. The window
    manager may open the window at some other size, in which case this is a
    slightly wrong starting position for a splitter the user can drag, which is
    the cheap failure of the two. }
  if (not panedSeeded) and (w > 0) then
  begin
    Split.Position := W_TREE;
    RightSplit.Position := H_WIN - BAR_H - H_LOG;
    panedSeeded := True;
  end;
end;

function GuiAutoQuit(data: Pointer): Integer; cdecl;
begin
  gtk_main_quit;
  GuiAutoQuit := 0;
end;

{ --gui-monitor-smoke PRESSES THE BUTTONS THE OWNER PRESSES.

  --gui-smoke opens the window, paints it and quits. It never starts a child, so
  it could not have caught the monitor hang, and the Stop button's path had never
  been driven under Xvfb at all -- the one control whose whole job is to give
  control back. These call the real OnMonitor/OnStop handlers, the same ones the
  toolbar buttons are wired to at f.MonBtn/f.StopBtn, so what is tested is the
  shipped path and not a model of it.

  If either handler fails to return, the mode never reaches its assertions and
  the harness's own timeout reports it -- which is the correct outcome for a
  hang, and better than a pass. }
function GuiSmokePressMonitor(data: Pointer): Integer; cdecl;
begin
  EspForm.OnMonitor(nil);
  GuiSmokePressMonitor := 0;
end;

function GuiSmokePressStop(data: Pointer): Integer; cdecl;
begin
  EspForm.OnStop(nil);
  GuiSmokePressStop := 0;
end;

{ --gui-libs-smoke drives Settings > Libraries, the IDE's SECOND TForm.

  What is worth checking is not the config parsing -- bochan already covers
  EspLibCfg round-trips headlessly -- but that the dialog CONSTRUCTS, gets
  populated from the project's espide.cfg, and CLOSES cleanly. The close path is
  the interesting half: GTK's default delete-event destroys a window, so a kept
  form whose title bar was closed would hand a stale handle to the next Show,
  which is why OnMenuLibraries rebuilds and OnLibClose nils the field. This
  asserts the field really is nil afterwards. }
var
  libsOpened: Boolean = False;
  libsCaption: AnsiString = '';

function GuiSmokePressLibs(data: Pointer): Integer; cdecl;
begin
  EspForm.OnMenuLibraries(nil);
  libsOpened := EspForm.LibDlg <> nil;
  if libsOpened then libsCaption := EspForm.LibDlg.Caption;
  GuiSmokePressLibs := 0;
end;

function GuiSmokeCloseLibs(data: Pointer): Integer; cdecl;
begin
  EspForm.OnLibClose(nil);
  GuiSmokeCloseLibs := 0;
end;

{ A toolbar button. NO SetBounds: a toolbar places its own items, and a size
  request on one becomes a width the row -- and therefore the window -- cannot
  go below, which is the floor this toolbar exists to remove. }
function MkButton(const cap: AnsiString): TButton;
var b: TButton;
begin
  b := TButton.Create(nil);
  b.Caption := cap;
  b.Parent := EspForm.Bar;
  MkButton := b;
end;

var
  arg, start, a: AnsiString;
  ai, pos1, smokeRc: Integer;
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

  { Arguments are scanned rather than read by position, because --port has to be
    passable to a headless --auto run: naming the board is how an automated run
    avoids touching anyone else's. Positional arguments keep their old meaning
    (project, then seconds) and --port is taken out of the sequence wherever it
    appears. }
  arg := '';
  start := f.RepoRoot + '/examples/esp32';
  f.AutoSecs := 10;
  ai := 1;
  pos1 := 0;
  while ai <= ParamCount do
  begin
    a := ParamStr(ai);
    if a = '--port' then
    begin
      if ai < ParamCount then begin f.AutoPort := ParamStr(ai + 1); Inc(ai); end
      else writeln(StdErr, 'espide: --port needs a device path');
    end
    else if a = '--auto' then
      f.AutoRun := True
    else if (a = '--gui-smoke') or (a = '--gui-monitor-smoke')
         or (a = '--gui-libs-smoke') then
      arg := a
    else
    begin
      Inc(pos1);
      if pos1 = 1 then start := a
      else if pos1 = 2 then f.AutoSecs := StrToIntDef(a, 10);
    end;
    Inc(ai);
  end;
  if f.AutoPort <> '' then
    writeln('espide: port fixed to ', f.AutoPort, ' -- no other port will be opened');

  { THE TOOLBAR IS A REAL GtkToolbar, and that is what unfloors the window.
    These nine controls used to sit at absolute coordinates out to x=934, so
    the form's container reported 936 as its MINIMUM width and the window
    could not be dragged narrower than that however empty it looked. A
    toolbar moves the items that no longer fit into its own arrow menu. }
  { A vertical box holds the toolbar over the status line, and the box is the
    form's header. The status LABEL is the reason for the box: on the
    absolute-coordinate container it needed a width, and a width request is a
    minimum -- it made the window's floor track the label instead of the
    toolbar. In a vertical box it gets the full width for free and can say
    anything without widening anything. }
  f.HeadBox := TBox.Create(nil);
  f.HeadBox.Vertical := True;
  f.HeadBox.Parent := f;

  f.Bar := TToolBar.Create(nil);
  f.Bar.Parent := f.HeadBox;

  f.RootEdit := TEdit.Create(nil);
  f.RootEdit.Parent := f.Bar;
  { the ONE size request left in the row, and it is the first item, so it is
    the whole of the window's remaining width floor }
  f.RootEdit.SetBounds(0, 0, 240, 28);
  f.OpenBtn := MkButton('Open');
  f.Bar.AddSeparator;
  f.ChipLbl := TLabel.Create(nil);
  f.ChipLbl.Caption := ' Chip: ';
  f.ChipLbl.Parent := f.Bar;
  f.ChipBox := TComboBox.Create(nil);
  f.ChipBox.Parent := f.Bar;
  f.ChipBox.AddItem('auto');
  f.ChipBox.AddItem('ESP32');
  f.ChipBox.AddItem('ESP32-S3');
  f.ChipBox.AddItem('ESP32-C3');
  f.ChipBox.AddItem('ESP32-S2');
  { The port selector. It is filled by RelistBoards, from by-id names only, and
    it is what makes Detect safe on a host with more than one board: a chip name
    can be ambiguous between two boards, a port cannot. }
  f.PortLbl := TLabel.Create(nil);
  f.PortLbl.Caption := ' Port: ';
  f.PortLbl.Parent := f.Bar;
  f.PortBox := TComboBox.Create(nil);
  f.PortBox.Parent := f.Bar;
  f.PortBox.AddItem('auto');
  f.PortBox.Text := 'auto';
  f.DetectBtn := MkButton('Detect');
  f.Bar.AddSeparator;
  f.SaveBtn := MkButton('Save');
  f.BuildBtn := MkButton('Build+Flash');
  f.MonBtn := MkButton('Monitor');
  f.StopBtn := MkButton('Stop');

  f.Status := TLabel.Create(nil);
  { '...' rather than widen: the status text is a sentence, and a label's
    minimum width is its whole text, so without this the WINDOW's minimum
    width tracked whatever the status line happened to say -- 505px, and a
    different number for a different project. }
  f.Status.Ellipsize := True;
  f.Status.Parent := f.HeadBox;

  f.BoardBar := TLabel.Create(nil);
  f.BoardBar.Ellipsize := True;
  f.BoardBar.Parent := f.HeadBox;

  f.Split := TPaned.Create(nil);
  f.Split.Parent := f;
  f.Split.SetBounds(0, 0, W_WIN, H_WIN - BAR_H);
  f.Tree := TTreeView.Create(nil);
  f.Tree.Parent := f.Split;
  f.RightSplit := TPaned.Create(nil);
  f.RightSplit.Vertical := True;
  f.RightSplit.Parent := f.Split;
  f.Editor := TMemo.Create(nil);
  f.Editor.Parent := f.RightSplit;
  f.Log := TMemo.Create(nil);
  f.Log.Parent := f.RightSplit;
  f.BuildMenu;
  f.Split.Position := W_TREE;
  f.RightSplit.Position := H_WIN - BAR_H - H_LOG;
  { The splitter pair IS the window's content: GTK sizes it, so the window
    resizes freely in both directions and no OnResize arithmetic reflows it.
    BAR_H is the strip above it that keeps absolute coordinates -- the toolbar
    row and the status line. }
  f.SetHeader(f.HeadBox);
  f.SetClient(f.Split, 0);

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

  { a relative folder is the caller's first (espide.sh runs from any CWD),
    else the checkout's: `espide examples/esp32/hello-s3` works anywhere }
  if (start <> '') and (start[1] <> '/') then
  begin
    if DirectoryExists(ExpandFileName(start)) then
      start := ExpandFileName(start)
    else
      start := f.RepoRoot + '/' + start;
  end;
  { ---- what the environment offers, read ONCE and from FILES ONLY ----
    Neither of these starts a child process and neither opens a port, so both
    are safe on the paint path and both are honest before anything is
    detected: issue 5 (what is attached) and issue 6 (is ESP-IDF installed). }
  f.Idf := EspDetectIdf;
  f.Dialout := EspDialoutState;
  { `sg dialout -c` is the owner's sanctioned route for a login that predates
    the group grant -- no sudo. Only offered when the user IS in the group in
    /etc/group (sg would fail otherwise) and sg is actually installed; a
    missing sg must not turn every serial command into a shell error. }
  f.UseSg := (f.Dialout = edMember) and
             (FileExists('/usr/bin/sg') or FileExists('/bin/sg'));
  f.RelistBoards;

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
  else if arg = '--gui-monitor-smoke' then
  begin
    { The port must be the pinned one and nothing else: OnMonitor falls back to
      "the only attached board" when MonitorPort is empty, and on a host with
      three boards that is somebody else's. }
    if f.AutoPort <> '' then f.MonitorPort := f.AutoPort;
    g_timeout_add(600, @GuiSmokePressMonitor, nil);
    g_timeout_add(600 + f.AutoSecs * 1000, @GuiSmokePressStop, nil);
    g_timeout_add(600 + f.AutoSecs * 1000 + 1200, @GuiAutoQuit, nil);
    Application.Run;
    smokeRc := 0;
    { Every check reports rather than the first one winning, because "Stop left
      the child running" and "the monitor never opened" are different bugs and
      seeing both at once is worth more than seeing the earlier one. }
    if f.Proc.Running then
    begin
      writeln('GUI MONITOR SMOKE FAIL: Stop returned but left the child running');
      smokeRc := 1;
    end;
    if f.Mode <> mIdle then
    begin
      writeln('GUI MONITOR SMOKE FAIL: mode is not idle after Stop');
      smokeRc := 1;
    end;
    if Pos('--- serial ', f.LogText) = 0 then
    begin
      writeln('GUI MONITOR SMOKE FAIL: the monitor never opened the port');
      smokeRc := 1;
    end;
    if Pos('--- stopped ---', f.LogText) = 0 then
    begin
      writeln('GUI MONITOR SMOKE FAIL: Stop did not log that it stopped');
      smokeRc := 1;
    end;
    if smokeRc = 0 then
      writeln('GUI MONITOR SMOKE OK: pressed Monitor, held it ', f.AutoSecs,
              ' s, pressed Stop, control came back (log ',
              Length(f.LogText), ' bytes)');
    Halt(smokeRc);
  end
  else if arg = '--gui-libs-smoke' then
  begin
    { DO NOT press it with no project open. OnMenuLibraries answers that case
      with ShowMessage, which is MODAL, and a modal dialog under Xvfb with nobody
      to click it is indistinguishable from a hang. Refuse here instead, where the
      reason can be printed. }
    if f.CurProject = '' then
    begin
      writeln('GUI LIBS SMOKE FAIL: no project open in ', start,
              ' -- pass a folder holding a CMakeLists.txt and a build.sh');
      Halt(1);
    end;
    g_timeout_add(600, @GuiSmokePressLibs, nil);
    g_timeout_add(1800, @GuiSmokeCloseLibs, nil);
    g_timeout_add(2600, @GuiAutoQuit, nil);
    Application.Run;
    smokeRc := 0;
    if not libsOpened then
    begin
      writeln('GUI LIBS SMOKE FAIL: the Libraries dialog did not open');
      smokeRc := 1;
    end;
    if Pos('Libraries for ', libsCaption) <> 1 then
    begin
      writeln('GUI LIBS SMOKE FAIL: caption does not name the project: ', libsCaption);
      smokeRc := 1;
    end;
    if f.LibDlg <> nil then
    begin
      writeln('GUI LIBS SMOKE FAIL: closing left the form behind, so the next ' +
              'open would reuse a destroyed handle');
      smokeRc := 1;
    end;
    if smokeRc = 0 then
      writeln('GUI LIBS SMOKE OK: opened "', libsCaption,
              '", populated it from espide.cfg, closed it, field cleared');
    Halt(smokeRc);
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
