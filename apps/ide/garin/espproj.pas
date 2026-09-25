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

{ Display name of an IDF target: 'esp32s3' -> 'ESP32-S3'. }
function EspChipLabel(const chip: AnsiString): AnsiString;

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

procedure WalkTree(const root, rel: AnsiString; depth, maxDepth: Integer;
                   var outA: TStrArray);
var sr: TSearchRec;
    dirs, files: TStrArray;
    i: Integer;
    full: AnsiString;
begin
  SetLength(dirs, 0);
  SetLength(files, 0);
  if rel = '' then full := root else full := JoinPath(root, rel);
  if FindFirst(JoinPath(full, '*'), faDirectory, sr) = 0 then
  begin
    repeat
      if not SkipEntry(sr.Name) then
      begin
        if (sr.Attr and faDirectory) <> 0 then
        begin
          SetLength(dirs, Length(dirs) + 1);
          dirs[Length(dirs) - 1] := sr.Name;
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
    SetLength(outA, Length(outA) + 1);
    outA[Length(outA) - 1] := rel + dirs[i] + '/';
    if depth < maxDepth then
      WalkTree(root, rel + dirs[i] + '/', depth + 1, maxDepth, outA);
  end;
  for i := 0 to Length(files) - 1 do
  begin
    SetLength(outA, Length(outA) + 1);
    outA[Length(outA) - 1] := rel + files[i];
  end;
end;

function EspListTree(const root: AnsiString; maxDepth: Integer): TStrArray;
var a: TStrArray;
begin
  SetLength(a, 0);
  WalkTree(StripSlash(root), '', 0, maxDepth, a);
  EspListTree := a;
end;

end.
