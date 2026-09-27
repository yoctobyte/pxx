unit espproj;

{ garin/espproj — the render-agnostic half of the ESP32 face: which folder is a
  buildable ESP-IDF project, which chip a project builds for, which chip a board
  says it is, and whether those agree. No GTK here; bochan tests all of it
  headlessly.

  A project is what tools/esp_flash.sh --project accepts: a folder with a
  CMakeLists.txt and an executable build.sh (examples/esp32/<name>-<chip>). The
  build is delegated to that build.sh, so this unit never re-derives flags. }

interface

uses sysutils, buffer, project;

{ One sentence refusing a folder that is not a buildable ESP-IDF project, or ''
  when it is one. }
function EspProjectProblem(const dir: AnsiString): AnsiString;

{ Walk up from path (a file or folder) to the nearest folder that is a project,
  stopping at stopAt. '' when there is none. }
function EspFindProjectRoot(const path, stopAt: AnsiString): AnsiString;

{ The chip a project builds for, as an IDF target name ('esp32s3'), or '' when
  the project does not say. Same order as the projects themselves use: the
  folder suffix (-s3/-c3/-s2, tools/esp_flash.sh's rule), then a single
  `set-target <chip>` in build.sh, then CONFIG_IDF_TARGET in sdkconfig. }
function EspProjectChip(const dir: AnsiString): AnsiString;

{ The chip in `esptool chip-id` output ('Connected to ESP32-S3 on ...'), as an
  IDF target name, or '' when no chip answered. }
function EspChipFromEsptool(const outp: AnsiString): AnsiString;

{ Why esptool could not talk to a port, in words, or '' when nothing is wrong
  that we recognise. }
function EspPortProblem(const outp: AnsiString): AnsiString;

{ The serial ports a board can be on: /dev/ttyACM* and /dev/ttyUSB*, sorted. }
function EspCandidatePorts: TStrArray;

{ Decide the chip to build for. selector is 'auto' or an IDF target name;
  detected is the board's chip ('' when none answered); projChip is
  EspProjectChip ('' when the project does not say). On success returns True
  and sets chip; otherwise returns False and sets why to one plain sentence.
  'auto' with no board is a refusal, never a default chip. }
function EspDecideChip(const selector, detected, projChip: AnsiString;
                       var chip, why: AnsiString): Boolean;

{ The files and folders under root, as root-relative paths in tree order
  (folders end in '/'), skipping hidden entries and build output. }
function EspListTree(const root: AnsiString; maxDepth: Integer): TStrArray;

{ The entries of ONE directory: sub-directories first, then files, each group
  sorted, hidden and generated names dropped. A directory carries a trailing
  '/' so a caller can tell the two apart without asking the filesystem again.

  This is the single place the tree's ORDER and FILTER live -- EspListTree is
  this function applied recursively, so the flat listing and a collapsible
  tree built one level at a time can never disagree about what is shown. }
function EspListDir(const dir: AnsiString): TStrArray;

{ Display name of an IDF target: 'esp32s3' -> 'ESP32-S3'. }
function EspChipLabel(const chip: AnsiString): AnsiString;

{ ---- attached boards, WITHOUT opening a port ---- }

type
  { One attached board. Port is what to hand esptool. Chip/Mac/Revision are ''
    until Detect has asked the board, and asking RESETS it -- which is why they
    are separate fields and not part of the listing. }
  TEspBoard = record
    Port: AnsiString;       { /dev/serial/by-id/<name> -- stable across replug }
    Name: AnsiString;       { the by-id basename }
    Bridge: AnsiString;     { 'CP2102', 'native USB-JTAG', 'CH34x', ... or '' }
    Chip: AnsiString;       { IDF target name, after Detect }
    Mac: AnsiString;
    Revision: AnsiString;
  end;
  TEspBoardArr = array of TEspBoard;

{ Which USB-serial bridge a by-id name describes, in the words a user would
  recognise, or '' when the name is not one we know.

  FROM THE NAME AND NOT FROM sysfs, DELIBERATELY, AND THE REASON IS A GAP RATHER
  THAN A PREFERENCE. The authoritative answer is idVendor/idProduct under
  /sys/class/tty/<tty>/device/.., and reaching it needs the tty behind the by-id
  symlink -- which needs readlink(2), which the RTL does not have (it routes
  syscalls through platform.pas's PAL, and adding one there is per-platform work
  across three backends). So this reads udev's OWN rendering of the USB
  descriptors, which is what the by-id name is, rather than guessing: udev built
  the string from the very fields we would otherwise go and read. Nothing here
  opens anything. }
function EspBridgeFromByIdName(const nm: AnsiString): AnsiString;

{ Every board attached, read ONLY from a directory of by-id names. Opens no
  port: listing must never reset a board, because a reset interrupts whatever it
  is running. byIdDir is a parameter so this is testable against a fixture tree
  of real symlinks. Entries are returned sorted, with Chip/Mac/Revision blank. }
function EspListBoardsIn(const byIdDir: AnsiString): TEspBoardArr;

{ EspListBoardsIn('/dev/serial/by-id'). }
function EspListBoards: TEspBoardArr;

{ One line describing a board, for a status bar or a list: the bridge, the
  by-id name, and the chip/revision/MAC when Detect has filled them in. }
function EspBoardLine(const b: TEspBoard): AnsiString;

{ The MAC in `esptool chip-id` output ('MAC: e0:8c:fe:57:bb:b8'), or ''. }
function EspMacFromEsptool(const outp: AnsiString): AnsiString;

{ The silicon revision in `Chip is ESP32-D0WD-V3 (revision v3.1)', or ''. }
function EspRevisionFromEsptool(const outp: AnsiString): AnsiString;

{ ---- the dialout group, and the route around a stale login ---- }

type
  { edMember: the user is in dialout in /etc/group. A LOGIN that predates the
    change still has no such group in its process credentials, so a command may
    need `sg dialout -c`; that is the owner's sanctioned route and it needs no
    sudo. edNotMember: nothing will work until the group is granted.
    edUnknown: /etc/group could not be read, so say nothing rather than a wrong
    thing. }
  TEspDialout = (edUnknown, edMember, edNotMember);

{ Membership from the TEXT of a group file, so it is testable: parses
  `dialout:x:20:readsb,neo`. Never touches the filesystem. }
function EspDialoutFromGroupText(const groupText, user: AnsiString): TEspDialout;

{ EspDialoutFromGroupText of /etc/group and $USER (or $LOGNAME). }
function EspDialoutState: TEspDialout;

{ One sentence for the status bar: how serial access is being obtained, or what
  the user must do. '' for edMember with nothing to say. }
function EspDialoutNote(st: TEspDialout): AnsiString;

{ s quoted so /bin/sh -c sees exactly s, single-quote safe. `sg dialout -c`
  takes ONE string and forwards no arguments, so a port path cannot be passed as
  $1 and has to be quoted into the command. }
function EspShellQuote(const s: AnsiString): AnsiString;

{ inner, wrapped in `sg dialout -c` when useSg. }
function EspWrapSg(const inner: AnsiString; useSg: Boolean): AnsiString;

{ ---- is ESP-IDF installed, and which version ---- }

type
  TEspIdf = record
    Found: Boolean;
    Path: AnsiString;       { the IDF checkout }
    Version: AnsiString;    { '6.0.1', or '' when the header could not be read }
    PyEnv: AnsiString;      { the ~/.espressif python env directory name }
    Advice: AnsiString;     { where to get it, when not Found }
  end;

{ Where ESP-IDF is and which version, from FILES only -- no child process, so
  this is safe to call while painting and is testable against a fake tree.
  envPath is $IDF_PATH (may be ''); homeDir is $HOME. Order: envPath, then
  homeDir/esp/esp-idf. The version comes from
  components/esp_common/include/esp_idf_version.h, which is the header IDF
  itself compiles against -- not from `git describe`, which needs a child, and
  not from version.txt, which a git checkout does not have (measured
  2026-09-27: ~/esp/esp-idf has no version.txt and the header says 6.0.1). }
function EspDetectIdfIn(const envPath, homeDir: AnsiString): TEspIdf;

{ EspDetectIdfIn($IDF_PATH, $HOME). }
function EspDetectIdf: TEspIdf;

{ One line for the status bar / About. }
function EspIdfLine(const inf: TEspIdf): AnsiString;

{ ---- per-project extra libraries and components ---- }

type
  { What a project needs beyond its own folder: extra unit search roots for pxx
    (-Fu) and extra ESP-IDF components (EXTRA_COMPONENT_DIRS / REQUIRES, the
    way examples/esp32/nilpy-station-s3 reaches pxx_esp). }
  TEspLibCfg = record
    UnitDirs: TStrArray;
    ComponentDirs: TStrArray;
    Requires: TStrArray;
  end;

{ Where the settings live: <project>/espide.cfg. In the PROJECT folder, so it
  travels with the project and a second checkout of it builds the same. }
function EspLibCfgPath(const projectDir: AnsiString): AnsiString;

{ Parse the file text. Unknown keys and comments are ignored rather than
  refused, so a newer IDE's file still loads here. }
function EspLibCfgParse(const text: AnsiString): TEspLibCfg;

{ Render for writing. Parse(Render(c)) = c, which bochan asserts. }
function EspLibCfgRender(const c: TEspLibCfg): AnsiString;

function EspLibCfgLoad(const projectDir: AnsiString): TEspLibCfg;
function EspLibCfgSave(const projectDir: AnsiString; const c: TEspLibCfg): Boolean;

{ True when nothing is configured -- the common case, and worth not printing. }
function EspLibCfgEmpty(const c: TEspLibCfg): Boolean;

{ The -Fu arguments a build should add, one per unit dir. }
function EspLibCfgPxxFlags(const c: TEspLibCfg): TStrArray;

{ One line for the status bar: how many of each, or ''. }
function EspLibCfgLine(const c: TEspLibCfg): AnsiString;

{ ---- which compiler this checkout builds with ---- }

type
  TEspPin = record
    Version: AnsiString;   { '441' }
    Sha: AnsiString;       { the pinned binary's sha256, full }
    Commit: AnsiString;    { the commit it was pinned from }
  end;

{ Parse stable_linux_amd64/default/pin.log. The LAST `pinned vN <sha> ...` line
  wins, which is the pin in place.

  FROM pin.log AND NOT FROM last.sha256, although that file is one line and
  right next to it: last.sha256 names `latest`, and latest and pinned are
  different symlinks that are equal today and are not the same claim. pin.log
  says the word `pinned` in the row itself. }
function EspPinFromLogText(const logText: AnsiString): TEspPin;

{ EspPinFromLogText of <repoRoot>/stable_linux_amd64/default/pin.log, falling
  back to the VERSION file beside it when the log cannot be read. }
function EspPinInfo(const repoRoot: AnsiString): TEspPin;

{ One line for About: 'pxx pin v441 (4ebfa2d047a2)'. }
function EspPinLine(const p: TEspPin): AnsiString;

implementation

function ReadAll(const path: AnsiString): AnsiString;
var b: TIdeBuffer;
begin
  ReadAll := '';
  b := TIdeBuffer.Create;
  if b.LoadFromFile(path) then ReadAll := b.Text;
  b.Free;
end;

function JoinPath(const dir, name: AnsiString): AnsiString;
begin
  if (dir <> '') and (dir[Length(dir)] = '/') then
    JoinPath := dir + name
  else
    JoinPath := dir + '/' + name;
end;

function StripSlash(const dir: AnsiString): AnsiString;
var s: AnsiString;
begin
  s := dir;
  while (Length(s) > 1) and (s[Length(s)] = '/') do
    s := Copy(s, 1, Length(s) - 1);
  StripSlash := s;
end;

function EspProjectProblem(const dir: AnsiString): AnsiString;
begin
  EspProjectProblem := '';
  if not DirectoryExists(dir) then
    EspProjectProblem := dir + ' is not a folder.'
  else if not (FileExists(JoinPath(dir, 'CMakeLists.txt')) and
               FileExists(JoinPath(dir, 'build.sh'))) then
    EspProjectProblem := ExtractFileName(StripSlash(dir)) +
      ' is not an ESP-IDF project (it has no CMakeLists.txt and build.sh): ' +
      'copy a project from examples/esp32 and put your main.pas or main.npy ' +
      'in its main/ folder.';
end;

function EspFindProjectRoot(const path, stopAt: AnsiString): AnsiString;
var d, stop: AnsiString;
    i: Integer;
begin
  EspFindProjectRoot := '';
  d := StripSlash(path);
  stop := StripSlash(stopAt);
  if not DirectoryExists(d) then
  begin
    i := Length(d);
    while (i > 0) and (d[i] <> '/') do Dec(i);
    if i <= 1 then Exit;
    d := Copy(d, 1, i - 1);
  end;
  while d <> '' do
  begin
    if EspProjectProblem(d) = '' then
    begin
      EspFindProjectRoot := d;
      Exit;
    end;
    if (d = stop) or (d = '/') then Exit;
    i := Length(d);
    while (i > 0) and (d[i] <> '/') do Dec(i);
    if i <= 1 then Exit;
    d := Copy(d, 1, i - 1);
  end;
end;

function LowerAscii(const s: AnsiString): AnsiString;
var i: Integer;
    r: AnsiString;
begin
  r := s;
  for i := 1 to Length(r) do
    if (r[i] >= 'A') and (r[i] <= 'Z') then r[i] := Chr(Ord(r[i]) + 32);
  LowerAscii := r;
end;

function IsTargetChar(c: Char): Boolean;
begin
  IsTargetChar := ((c >= 'a') and (c <= 'z')) or ((c >= '0') and (c <= '9'));
end;

{ The one target that follows every `marker` in text; '' when there is none or
  when two occurrences disagree (build.sh files that switch on the suffix name
  both chips, and then the suffix rule, not the text, decides). }
function SingleTargetAfter(const text, marker: AnsiString): AnsiString;
var rest, found, t: AnsiString;
    p, i: Integer;
begin
  SingleTargetAfter := '';
  found := '';
  rest := text;
  p := Pos(marker, rest);
  while p > 0 do
  begin
    rest := Copy(rest, p + Length(marker), Length(rest));
    i := 1;
    while (i <= Length(rest)) and ((rest[i] = ' ') or (rest[i] = '"')) do Inc(i);
    t := '';
    while (i <= Length(rest)) and IsTargetChar(rest[i]) do
    begin
      t := t + rest[i];
      Inc(i);
    end;
    if Copy(t, 1, 5) = 'esp32' then
    begin
      if (found <> '') and (found <> t) then Exit;
      found := t;
    end;
    p := Pos(marker, rest);
  end;
  SingleTargetAfter := found;
end;

function EspProjectChip(const dir: AnsiString): AnsiString;
var base, t: AnsiString;
    n: Integer;
begin
  base := LowerAscii(ExtractFileName(StripSlash(dir)));
  n := Length(base);
  if (n > 3) and (base[n - 2] = '-') then
  begin
    t := Copy(base, n - 1, 2);
    if (t = 's3') or (t = 'c3') or (t = 's2') then
    begin
      EspProjectChip := 'esp32' + t;
      Exit;
    end;
  end;
  t := SingleTargetAfter(ReadAll(JoinPath(dir, 'build.sh')), 'set-target');
  if t = '' then
    t := SingleTargetAfter(ReadAll(JoinPath(dir, 'sdkconfig')), 'CONFIG_IDF_TARGET=');
  EspProjectChip := t;
end;

function EspChipFromEsptool(const outp: AnsiString): AnsiString;
var p, q: Integer;
    rest, name, t: AnsiString;
    i: Integer;
begin
  EspChipFromEsptool := '';
  p := Pos('Connected to ', outp);
  if p = 0 then Exit;
  rest := Copy(outp, p + Length('Connected to '), 64);
  q := Pos(' on ', rest);
  if q = 0 then Exit;
  name := LowerAscii(Copy(rest, 1, q - 1));
  t := '';
  for i := 1 to Length(name) do
    if IsTargetChar(name[i]) then t := t + name[i];
  if Copy(t, 1, 5) = 'esp32' then EspChipFromEsptool := t;
end;

function EspPortProblem(const outp: AnsiString): AnsiString;
begin
  EspPortProblem := '';
  if Pos('Permission denied', outp) > 0 then
    EspPortProblem := 'permission denied: your user needs the dialout group ' +
      '(add it, then log in again)'
  else if Pos('port is busy', outp) > 0 then
    EspPortProblem := 'the port is busy: another program has it open'
  else if (Pos('No serial data received', outp) > 0) or
          (Pos('Failed to connect', outp) > 0) then
    EspPortProblem := 'no ESP chip answered on this port'
  else if (Pos('esptool: command not found', outp) > 0) or
          (Pos('esptool: not found', outp) > 0) then
    EspPortProblem := 'esptool was not found: is ESP-IDF installed ' +
      '(~/esp/esp-idf or ESP_IDF_DIR)?';
end;

procedure SortStrs(var a: TStrArray);
var i, j: Integer;
    t: AnsiString;
begin
  for i := 1 to Length(a) - 1 do
  begin
    t := a[i];
    j := i - 1;
    while (j >= 0) and (a[j] > t) do
    begin
      a[j + 1] := a[j];
      Dec(j);
    end;
    a[j + 1] := t;
  end;
end;

procedure AddMatches(var a: TStrArray; const mask: AnsiString);
var sr: TSearchRec;
begin
  if FindFirst('/dev/' + mask, faSysFile, sr) = 0 then   { a tty is a device: faSysFile, as in FPC }
  begin
    repeat
      if (sr.Name <> '.') and (sr.Name <> '..') then
      begin
        SetLength(a, Length(a) + 1);
        a[Length(a) - 1] := '/dev/' + sr.Name;
      end;
    until FindNext(sr) <> 0;
    FindClose(sr);
  end;
end;

function EspCandidatePorts: TStrArray;
var a: TStrArray;
begin
  SetLength(a, 0);
  AddMatches(a, 'ttyACM*');
  AddMatches(a, 'ttyUSB*');
  SortStrs(a);
  EspCandidatePorts := a;
end;

function EspChipLabel(const chip: AnsiString): AnsiString;
var s: AnsiString;
    i: Integer;
begin
  s := chip;
  for i := 1 to Length(s) do
    if (s[i] >= 'a') and (s[i] <= 'z') then s[i] := Chr(Ord(s[i]) - 32);
  if Copy(s, 1, 5) = 'ESP32' then
    if Length(s) > 5 then s := 'ESP32-' + Copy(s, 6, Length(s));
  EspChipLabel := s;
end;

function EspDecideChip(const selector, detected, projChip: AnsiString;
                       var chip, why: AnsiString): Boolean;
begin
  EspDecideChip := False;
  chip := '';
  why := '';
  if selector = 'auto' then
  begin
    if detected = '' then
    begin
      why := 'No board detected: connect an ESP32 board and press Detect, ' +
             'or pick the chip by hand.';
      Exit;
    end;
    chip := detected;
  end
  else
  begin
    if (detected <> '') and (detected <> selector) then
    begin
      why := 'The chip selector says ' + EspChipLabel(selector) +
             ' but the connected board is an ' + EspChipLabel(detected) + '.';
      Exit;
    end;
    chip := selector;
  end;
  if (projChip <> '') and (projChip <> chip) then
  begin
    why := 'This project builds for the ' + EspChipLabel(projChip) +
           ', not the ' + EspChipLabel(chip) + ': open a project for the ' +
           EspChipLabel(chip) + ' or connect an ' + EspChipLabel(projChip) + '.';
    chip := '';
    Exit;
  end;
  EspDecideChip := True;
end;

function SkipEntry(const name: AnsiString): Boolean;
begin
  SkipEntry := (name = '') or (name[1] = '.') or (name = 'build') or
               (name = 'managed_components');
end;

function EspListDir(const dir: AnsiString): TStrArray;
var sr: TSearchRec;
    dirs, files, a: TStrArray;
    i: Integer;
begin
  SetLength(dirs, 0);
  SetLength(files, 0);
  SetLength(a, 0);
  if FindFirst(JoinPath(StripSlash(dir), '*'), faDirectory, sr) = 0 then
  begin
    repeat
      if not SkipEntry(sr.Name) then
      begin
        if (sr.Attr and faDirectory) <> 0 then
        begin
          SetLength(dirs, Length(dirs) + 1);
          dirs[Length(dirs) - 1] := sr.Name + '/';
        end
        else
        begin
          SetLength(files, Length(files) + 1);
          files[Length(files) - 1] := sr.Name;
        end;
      end;
    until FindNext(sr) <> 0;
    FindClose(sr);
  end;
  SortStrs(dirs);
  SortStrs(files);
  for i := 0 to Length(dirs) - 1 do
  begin
    SetLength(a, Length(a) + 1);
    a[Length(a) - 1] := dirs[i];
  end;
  for i := 0 to Length(files) - 1 do
  begin
    SetLength(a, Length(a) + 1);
    a[Length(a) - 1] := files[i];
  end;
  EspListDir := a;
end;

{ EspListDir applied recursively, depth-first, with each name prefixed by the
  path it was found under. Directories keep their trailing '/'. }
procedure WalkTree(const root, rel: AnsiString; depth, maxDepth: Integer;
                   var outA: TStrArray);
var ents: TStrArray;
    i: Integer;
    full, e: AnsiString;
begin
  if rel = '' then full := root else full := JoinPath(root, rel);
  ents := EspListDir(full);
  for i := 0 to Length(ents) - 1 do
  begin
    e := ents[i];
    SetLength(outA, Length(outA) + 1);
    outA[Length(outA) - 1] := rel + e;
    if (e[Length(e)] = '/') and (depth < maxDepth) then
      WalkTree(root, rel + e, depth + 1, maxDepth, outA);
  end;
end;

function EspListTree(const root: AnsiString; maxDepth: Integer): TStrArray;
var a: TStrArray;
begin
  SetLength(a, 0);
  WalkTree(StripSlash(root), '', 0, maxDepth, a);
  EspListTree := a;
end;

{ ---- small text helpers (file-level: the pinned compiler has no nested
       routines, see lfmload.pas's header) ---- }

function SplitChar(const s: AnsiString; c: Char): TStrArray;
var a: TStrArray;
    i, start: Integer;
begin
  SetLength(a, 0);
  start := 1;
  for i := 1 to Length(s) + 1 do
    if (i > Length(s)) or (s[i] = c) then
    begin
      SetLength(a, Length(a) + 1);
      a[Length(a) - 1] := Copy(s, start, i - start);
      start := i + 1;
    end;
  SplitChar := a;
end;

procedure AddStr(var a: TStrArray; const s: AnsiString);
begin
  SetLength(a, Length(a) + 1);
  a[Length(a) - 1] := s;
end;

function HasSub(const hay, needle: AnsiString): Boolean;
begin
  HasSub := Pos(needle, hay) > 0;
end;

{ ---- attached boards ---- }

function EspBridgeFromByIdName(const nm: AnsiString): AnsiString;
var s: AnsiString;
begin
  s := LowerAscii(nm);
  EspBridgeFromByIdName := '';
  { ORDER MATTERS ONLY HERE: a native-USB part's name also contains 'usb', so
    the JTAG test has to come before anything that matches on 'usb' alone. }
  if HasSub(s, 'jtag') then EspBridgeFromByIdName := 'native USB-JTAG'
  else if HasSub(s, 'cp2102') then EspBridgeFromByIdName := 'CP2102'
  else if HasSub(s, 'cp210') or HasSub(s, 'silicon_labs') then
    EspBridgeFromByIdName := 'CP210x'
  else if HasSub(s, 'ch343') then EspBridgeFromByIdName := 'CH343'
  else if HasSub(s, 'ch340') then EspBridgeFromByIdName := 'CH340'
  else if HasSub(s, '1a86') or HasSub(s, 'qinheng') then
    { 1a86 is QinHeng: the CH34x family, and the by-id name does not always say
      which member ('USB_Single_Serial' is a CH343 or a CH9102). Answer the
      family rather than invent the member. }
    EspBridgeFromByIdName := 'CH34x'
  else if HasSub(s, 'ftdi') or HasSub(s, 'ft232') then
    EspBridgeFromByIdName := 'FT232';
end;

procedure SortBoards(var a: TEspBoardArr);
var i, j: Integer;
    t: TEspBoard;
begin
  for i := 1 to Length(a) - 1 do
  begin
    t := a[i];
    j := i - 1;
    while (j >= 0) and (a[j].Name > t.Name) do
    begin
      a[j + 1] := a[j];
      Dec(j);
    end;
    a[j + 1] := t;
  end;
end;

function EspListBoardsIn(const byIdDir: AnsiString): TEspBoardArr;
var a: TEspBoardArr;
    sr: TSearchRec;
    b: TEspBoard;
begin
  SetLength(a, 0);
  { faAnyFile and NOT faSymLink: without faSymLink a link is reported by its
    TARGET, which is what we want twice over -- the character device confirms
    the link resolves, and a stale by-id entry pointing at an unplugged board
    drops out instead of being listed as attached. }
  if FindFirst(JoinPath(byIdDir, '*'), faAnyFile, sr) = 0 then
  begin
    repeat
      { hidden entries skipped, which covers '.' and '..' and anything else a
        dot-name: a by-id directory holds devices, so a dotfile in one is not a
        board -- SkipEntry above takes the same view of the tree walk }
      if (sr.Name <> '') and (sr.Name[1] <> '.') then
      begin
        b.Name := sr.Name;
        b.Port := JoinPath(byIdDir, sr.Name);
        b.Bridge := EspBridgeFromByIdName(sr.Name);
        b.Chip := '';
        b.Mac := '';
        b.Revision := '';
        SetLength(a, Length(a) + 1);
        a[Length(a) - 1] := b;
      end;
    until FindNext(sr) <> 0;
    FindClose(sr);
  end;
  SortBoards(a);
  EspListBoardsIn := a;
end;

function EspListBoards: TEspBoardArr;
begin
  EspListBoards := EspListBoardsIn('/dev/serial/by-id');
end;

function EspBoardLine(const b: TEspBoard): AnsiString;
var s: AnsiString;
begin
  if b.Bridge <> '' then s := b.Bridge else s := 'unknown bridge';
  s := s + '  ' + b.Name;
  if b.Chip <> '' then
  begin
    s := s + '  -- ' + EspChipLabel(b.Chip);
    if b.Revision <> '' then s := s + ' rev ' + b.Revision;
    if b.Mac <> '' then s := s + ', MAC ' + b.Mac;
  end
  else
    { NOT "unknown chip": nothing has asked, and saying unknown reads as a
      failed question. Asking resets the board, which is why it is a button. }
    s := s + '  -- not asked yet (Detect)';
  EspBoardLine := s;
end;

function IsHexOrColon(c: Char): Boolean;
begin
  IsHexOrColon := ((c >= '0') and (c <= '9')) or ((c >= 'a') and (c <= 'f')) or
                  ((c >= 'A') and (c <= 'F')) or (c = ':');
end;

function EspMacFromEsptool(const outp: AnsiString): AnsiString;
var p, i: Integer;
    r: AnsiString;
begin
  EspMacFromEsptool := '';
  p := Pos('MAC: ', outp);
  if p = 0 then Exit;
  i := p + Length('MAC: ');
  r := '';
  while (i <= Length(outp)) and IsHexOrColon(outp[i]) do
  begin
    r := r + outp[i];
    Inc(i);
  end;
  { six octets and five colons, or it is not a MAC and we say nothing rather
    than half of one }
  if Length(r) = 17 then EspMacFromEsptool := LowerAscii(r);
end;

function EspRevisionFromEsptool(const outp: AnsiString): AnsiString;
var p, i: Integer;
    r: AnsiString;
begin
  EspRevisionFromEsptool := '';
  p := Pos('(revision ', outp);
  if p = 0 then Exit;
  i := p + Length('(revision ');
  r := '';
  while (i <= Length(outp)) and (outp[i] <> ')') do
  begin
    r := r + outp[i];
    Inc(i);
  end;
  if (i <= Length(outp)) and (r <> '') then EspRevisionFromEsptool := r;
end;

{ ---- dialout ---- }

function EspDialoutFromGroupText(const groupText, user: AnsiString): TEspDialout;
var lines, fields, members: TStrArray;
    i, j: Integer;
begin
  EspDialoutFromGroupText := edUnknown;
  if (groupText = '') or (user = '') then Exit;
  EspDialoutFromGroupText := edNotMember;
  lines := SplitChar(groupText, #10);
  for i := 0 to Length(lines) - 1 do
  begin
    fields := SplitChar(lines[i], ':');
    if (Length(fields) >= 4) and (fields[0] = 'dialout') then
    begin
      members := SplitChar(fields[3], ',');
      for j := 0 to Length(members) - 1 do
        if Trim(members[j]) = user then
        begin
          EspDialoutFromGroupText := edMember;
          Exit;
        end;
    end;
  end;
end;

function EspDialoutState: TEspDialout;
var u: AnsiString;
begin
  u := GetEnvironmentVariable('USER');
  if u = '' then u := GetEnvironmentVariable('LOGNAME');
  EspDialoutState := EspDialoutFromGroupText(ReadAll('/etc/group'), u);
end;

function EspDialoutNote(st: TEspDialout): AnsiString;
begin
  case st of
    edMember:
      { Said because it is SURPRISING, not because it failed: a login that
        predates the group grant has no dialout in its credentials, so the
        commands go through sg and the user should know why. }
      EspDialoutNote := 'serial access: through `sg dialout` (your login ' +
                        'predates the group; no sudo needed)';
    edNotMember:
      EspDialoutNote := 'serial access: your user is not in the dialout group ' +
                        '-- run `sudo usermod -aG dialout $USER`, then log in again';
  else
    EspDialoutNote := '';
  end;
end;

function EspShellQuote(const s: AnsiString): AnsiString;
var i: Integer;
    r: AnsiString;
begin
  r := '''';
  for i := 1 to Length(s) do
    if s[i] = '''' then r := r + '''\''''' else r := r + s[i];
  EspShellQuote := r + '''';
end;

function EspWrapSg(const inner: AnsiString; useSg: Boolean): AnsiString;
begin
  if useSg then
    EspWrapSg := 'sg dialout -c ' + EspShellQuote(inner)
  else
    EspWrapSg := inner;
end;

{ ---- ESP-IDF ---- }

function IntAfterDefine(const text, name: AnsiString): AnsiString;
var p, i: Integer;
    r: AnsiString;
begin
  IntAfterDefine := '';
  p := Pos('#define ' + name, text);
  if p = 0 then Exit;
  i := p + Length('#define ' + name);
  while (i <= Length(text)) and ((text[i] = ' ') or (text[i] = #9)) do Inc(i);
  r := '';
  while (i <= Length(text)) and (text[i] >= '0') and (text[i] <= '9') do
  begin
    r := r + text[i];
    Inc(i);
  end;
  IntAfterDefine := r;
end;

function FirstSubdir(const dir: AnsiString): AnsiString;
var sr: TSearchRec;
    names: TStrArray;
begin
  FirstSubdir := '';
  SetLength(names, 0);
  if FindFirst(JoinPath(dir, '*'), faDirectory, sr) = 0 then
  begin
    repeat
      if (sr.Name <> '.') and (sr.Name <> '..') and
         ((sr.Attr and faDirectory) <> 0) then AddStr(names, sr.Name);
    until FindNext(sr) <> 0;
    FindClose(sr);
  end;
  SortStrs(names);
  if Length(names) > 0 then FirstSubdir := names[0];
end;

function IdfAt(const dir: AnsiString; var inf: TEspIdf): Boolean;
var hdr, maj, min, pat: AnsiString;
begin
  IdfAt := False;
  if dir = '' then Exit;
  { tools/idf.py is the test, not the directory existing: an empty ~/esp/esp-idf
    left by a failed clone is not an install, and reporting it as one sends the
    user to debug the wrong thing. }
  if not FileExists(JoinPath(StripSlash(dir), 'tools/idf.py')) then Exit;
  inf.Found := True;
  inf.Path := StripSlash(dir);
  hdr := ReadAll(JoinPath(inf.Path, 'components/esp_common/include/esp_idf_version.h'));
  maj := IntAfterDefine(hdr, 'ESP_IDF_VERSION_MAJOR');
  min := IntAfterDefine(hdr, 'ESP_IDF_VERSION_MINOR');
  pat := IntAfterDefine(hdr, 'ESP_IDF_VERSION_PATCH');
  if (maj <> '') and (min <> '') then
  begin
    inf.Version := maj + '.' + min;
    if pat <> '' then inf.Version := inf.Version + '.' + pat;
  end;
  IdfAt := True;
end;

function EspDetectIdfIn(const envPath, homeDir: AnsiString): TEspIdf;
var inf: TEspIdf;
begin
  inf.Found := False;
  inf.Path := '';
  inf.Version := '';
  inf.PyEnv := '';
  inf.Advice := '';
  if not IdfAt(envPath, inf) then
    if not IdfAt(JoinPath(StripSlash(homeDir), 'esp/esp-idf'), inf) then
    begin
      inf.Advice := 'ESP-IDF was not found (looked at $IDF_PATH and ' +
        '~/esp/esp-idf). Install it from ' +
        'https://docs.espressif.com/projects/esp-idf/en/stable/get-started/ ' +
        'and re-run, or set IDF_PATH.';
      EspDetectIdfIn := inf;
      Exit;
    end;
  if homeDir <> '' then
    inf.PyEnv := FirstSubdir(JoinPath(StripSlash(homeDir), '.espressif/python_env'));
  EspDetectIdfIn := inf;
end;

function EspDetectIdf: TEspIdf;
begin
  EspDetectIdf := EspDetectIdfIn(GetEnvironmentVariable('IDF_PATH'),
                                 GetEnvironmentVariable('HOME'));
end;

function EspIdfLine(const inf: TEspIdf): AnsiString;
var s: AnsiString;
begin
  if not inf.Found then
  begin
    EspIdfLine := 'ESP-IDF: not found';
    Exit;
  end;
  s := 'ESP-IDF ';
  if inf.Version <> '' then s := s + inf.Version else s := s + '(version unknown)';
  s := s + ' at ' + inf.Path;
  if inf.PyEnv <> '' then s := s + ' (python env ' + inf.PyEnv + ')';
  EspIdfLine := s;
end;

{ ---- per-project libraries ---- }

function EspLibCfgPath(const projectDir: AnsiString): AnsiString;
begin
  EspLibCfgPath := JoinPath(StripSlash(projectDir), 'espide.cfg');
end;

function EspLibCfgParse(const text: AnsiString): TEspLibCfg;
var c: TEspLibCfg;
    lines: TStrArray;
    i, eq: Integer;
    ln, key, val: AnsiString;
begin
  SetLength(c.UnitDirs, 0);
  SetLength(c.ComponentDirs, 0);
  SetLength(c.Requires, 0);
  lines := SplitChar(text, #10);
  for i := 0 to Length(lines) - 1 do
  begin
    ln := Trim(lines[i]);
    if (ln = '') or (ln[1] = '#') or (ln[1] = ';') then Continue;
    eq := Pos('=', ln);
    if eq = 0 then Continue;
    key := LowerAscii(Trim(Copy(ln, 1, eq - 1)));
    val := Trim(Copy(ln, eq + 1, Length(ln)));
    if val = '' then Continue;
    { UNKNOWN KEYS ARE IGNORED, not refused: a file written by a later IDE must
      still open here, and a refusal would lose the keys this version does
      understand along with the one it does not. }
    if key = 'unit-dir' then AddStr(c.UnitDirs, val)
    else if key = 'component-dir' then AddStr(c.ComponentDirs, val)
    else if key = 'require' then AddStr(c.Requires, val);
  end;
  EspLibCfgParse := c;
end;

function EspLibCfgRender(const c: TEspLibCfg): AnsiString;
var s: AnsiString;
    i: Integer;
begin
  s := '# espide project settings -- edit here or in Settings > Libraries.' + #10 +
       '# unit-dir: an extra pxx unit search root (becomes -Fu<dir>)' + #10 +
       '# component-dir: an extra ESP-IDF component root (EXTRA_COMPONENT_DIRS)' + #10 +
       '# require: an ESP-IDF component this project REQUIREs' + #10;
  for i := 0 to Length(c.UnitDirs) - 1 do
    s := s + 'unit-dir = ' + c.UnitDirs[i] + #10;
  for i := 0 to Length(c.ComponentDirs) - 1 do
    s := s + 'component-dir = ' + c.ComponentDirs[i] + #10;
  for i := 0 to Length(c.Requires) - 1 do
    s := s + 'require = ' + c.Requires[i] + #10;
  EspLibCfgRender := s;
end;

function EspLibCfgLoad(const projectDir: AnsiString): TEspLibCfg;
begin
  EspLibCfgLoad := EspLibCfgParse(ReadAll(EspLibCfgPath(projectDir)));
end;

function EspLibCfgSave(const projectDir: AnsiString; const c: TEspLibCfg): Boolean;
begin
  EspLibCfgSave := WriteAllText(EspLibCfgPath(projectDir), EspLibCfgRender(c));
end;

function EspLibCfgEmpty(const c: TEspLibCfg): Boolean;
begin
  EspLibCfgEmpty := (Length(c.UnitDirs) = 0) and (Length(c.ComponentDirs) = 0) and
                    (Length(c.Requires) = 0);
end;

function EspLibCfgPxxFlags(const c: TEspLibCfg): TStrArray;
var a: TStrArray;
    i: Integer;
begin
  SetLength(a, 0);
  for i := 0 to Length(c.UnitDirs) - 1 do
    AddStr(a, '-Fu' + c.UnitDirs[i]);
  EspLibCfgPxxFlags := a;
end;

function SplitWhite(const s: AnsiString): TStrArray;
var a: TStrArray;
    i, start: Integer;
begin
  SetLength(a, 0);
  start := 0;
  for i := 1 to Length(s) + 1 do
    if (i > Length(s)) or (s[i] = ' ') or (s[i] = #9) then
    begin
      if start > 0 then AddStr(a, Copy(s, start, i - start));
      start := 0;
    end
    else if start = 0 then start := i;
  SplitWhite := a;
end;

function EspPinFromLogText(const logText: AnsiString): TEspPin;
var p: TEspPin;
    lines, f: TStrArray;
    i, j: Integer;
begin
  p.Version := '';
  p.Sha := '';
  p.Commit := '';
  lines := SplitChar(logText, #10);
  for i := 0 to Length(lines) - 1 do
  begin
    f := SplitWhite(lines[i]);
    { <iso-ts> pinned vN <sha> (was <old>) <commit> -- the LAST such row is the
      pin in place, so keep overwriting rather than stopping at the first }
    if (Length(f) >= 4) and (f[1] = 'pinned') and (Copy(f[2], 1, 1) = 'v') then
    begin
      p.Version := Copy(f[2], 2, Length(f[2]));
      p.Sha := f[3];
      j := Length(f) - 1;
      if j >= 4 then p.Commit := f[j] else p.Commit := '';
    end;
  end;
  EspPinFromLogText := p;
end;

function EspPinInfo(const repoRoot: AnsiString): TEspPin;
var p: TEspPin;
    base, v: AnsiString;
    i: Integer;
begin
  base := JoinPath(StripSlash(repoRoot), 'stable_linux_amd64/default');
  p := EspPinFromLogText(ReadAll(JoinPath(base, 'pin.log')));
  if p.Version = '' then
  begin
    { a release tarball ships the pin without its history }
    v := Trim(ReadAll(JoinPath(base, 'VERSION')));
    for i := 1 to Length(v) do
      if (v[i] < '0') or (v[i] > '9') then
      begin
        v := Copy(v, 1, i - 1);
        Break;
      end;
    p.Version := v;
  end;
  EspPinInfo := p;
end;

function EspPinLine(const p: TEspPin): AnsiString;
var s: AnsiString;
begin
  if p.Version = '' then
  begin
    EspPinLine := 'pxx pin: unknown';
    Exit;
  end;
  s := 'pxx pin v' + p.Version;
  if p.Sha <> '' then s := s + ' (' + Copy(p.Sha, 1, 12) + ')';
  if p.Commit <> '' then s := s + ' from ' + Copy(p.Commit, 1, 10);
  EspPinLine := s;
end;

function EspLibCfgLine(const c: TEspLibCfg): AnsiString;
var s: AnsiString;
begin
  if EspLibCfgEmpty(c) then
  begin
    EspLibCfgLine := '';
    Exit;
  end;
  s := 'libraries:';
  if Length(c.UnitDirs) > 0 then
    s := s + ' ' + IntToStr(Length(c.UnitDirs)) + ' unit root(s)';
  if Length(c.ComponentDirs) > 0 then
    s := s + ' ' + IntToStr(Length(c.ComponentDirs)) + ' component root(s)';
  if Length(c.Requires) > 0 then
    s := s + ' ' + IntToStr(Length(c.Requires)) + ' require(s)';
  EspLibCfgLine := s;
end;

end.
