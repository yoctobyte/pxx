program fm;
{ Terminal file browser demo.

  Usage:
    fm [--compact|--tile] [--interactive] [path ...]

  The default mode renders once and exits for deterministic compile/run smoke.
  `--interactive` enables raw-key navigation: 1..4 pane count, Tab focus,
  j/k selection, o open directory, u parent, t view mode, q quit. }

uses sysutils, platform, hashing, png, image, ansiterm, ansirender;

const
  VIEW_COMPACT = 0;
  VIEW_TILE    = 1;
  MAX_PANES    = 4;

var
  List0, List1, List2, List3: TFileInfoArray;
  Paths: array[0..3] of AnsiString;
  Selected: array[0..3] of Integer;
  PaneCount, FocusPane, ViewMode: Integer;
  Interactive: Boolean;

function ListLen(pane: Integer): Integer;
begin
  if pane = 0 then Result := Length(List0)
  else if pane = 1 then Result := Length(List1)
  else if pane = 2 then Result := Length(List2)
  else Result := Length(List3);
end;

function EntryName(pane, idx: Integer): AnsiString;
begin
  if pane = 0 then Result := List0[idx].Name
  else if pane = 1 then Result := List1[idx].Name
  else if pane = 2 then Result := List2[idx].Name
  else Result := List3[idx].Name;
end;

function EntryIsDir(pane, idx: Integer): Boolean;
begin
  if pane = 0 then Result := List0[idx].IsDir
  else if pane = 1 then Result := List1[idx].IsDir
  else if pane = 2 then Result := List2[idx].IsDir
  else Result := List3[idx].IsDir;
end;

function EntrySize(pane, idx: Integer): Int64;
begin
  if pane = 0 then Result := List0[idx].Size
  else if pane = 1 then Result := List1[idx].Size
  else if pane = 2 then Result := List2[idx].Size
  else Result := List3[idx].Size;
end;

function Fit(const s: AnsiString; width: Integer): AnsiString;
begin
  if width <= 0 then
  begin
    Result := '';
    Exit;
  end;
  if Length(s) > width then
  begin
    if width = 1 then
      Result := '~'
    else
      Result := Copy(s, 1, width - 1) + '~';
  end
  else
    Result := PadRight(s, width, ' ');
end;

function JoinPath(const dir, name: AnsiString): AnsiString;
begin
  if dir = '/' then
    Result := '/' + name
  else if dir = '' then
    Result := name
  else
    Result := dir + '/' + name;
end;

function ParentPath(const path: AnsiString): AnsiString;
var i: Integer;
begin
  Result := '.';
  if (path = '') or (path = '.') or (path = '/') then Exit;
  i := Length(path);
  while (i > 1) and (path[i] = '/') do i := i - 1;
  while (i > 1) and (path[i] <> '/') do i := i - 1;
  if i <= 1 then
  begin
    if path[1] = '/' then Result := '/' else Result := '.';
  end
  else
    Result := Copy(path, 1, i - 1);
end;

function HasSuffix(const s, suffix: AnsiString): Boolean;
var ls, le: Integer;
begin
  ls := Length(s);
  le := Length(suffix);
  Result := (ls >= le) and (LowerCase(Copy(s, ls - le + 1, le)) = LowerCase(suffix));
end;

function LoadFileBytes(const path: AnsiString; var bytes: TByteArray; maxBytes: Integer): Boolean;
var
  handle: Integer;
  buf: array[0..1023] of Byte;
  readBytes: Int64;
  want, currLen, i: Integer;
begin
  Result := False;
  SetLength(bytes, 0);
  handle := PalOpen(PChar(path), PAL_OPEN_READ, 0);
  if handle < 0 then Exit;

  currLen := 0;
  repeat
    want := 1024;
    if (maxBytes > 0) and (currLen + want > maxBytes) then
      want := maxBytes - currLen;
    if want <= 0 then
      readBytes := 0
    else
      readBytes := PalRead(handle, @buf[0], want);
    if readBytes > 0 then
    begin
      SetLength(bytes, currLen + Integer(readBytes));
      for i := 0 to Integer(readBytes) - 1 do
        bytes[currLen + i] := buf[i];
      currLen := currLen + Integer(readBytes);
    end;
  until readBytes <= 0;

  PalClose(handle);
  Result := currLen > 0;
end;

function TextPreview(const path: AnsiString; width, maxLines: Integer): AnsiString;
var
  bytes: TByteArray;
  i, lineCount: Integer;
  line: AnsiString;
  b: Byte;
begin
  Result := '';
  if not LoadFileBytes(path, bytes, 2048) then Exit;
  line := '';
  lineCount := 0;
  for i := 0 to Length(bytes) - 1 do
  begin
    b := bytes[i];
    if (b = 10) or (lineCount >= maxLines) then
    begin
      Result := Result + Fit(line, width) + #10;
      line := '';
      lineCount := lineCount + 1;
      if lineCount >= maxLines then Break;
    end
    else if b <> 13 then
    begin
      if Length(line) < width then
      begin
        if (b >= 32) and (b < 127) then
          line := line + Chr(b)
        else
          line := line + '.';
      end;
    end;
  end;
  if (lineCount < maxLines) and (line <> '') then
    Result := Result + Fit(line, width) + #10;
end;

function PngPreview(const path: AnsiString; width, height: Integer): AnsiString;
var
  bytes: TByteArray;
  img: TImage;
begin
  Result := '';
  if not LoadFileBytes(path, bytes, 262144) then Exit;
  if PngDecodeRGBA(bytes, img) then
  begin
    Result := RenderAnsiTrueColorQuadrant(img, width, height) + AnsiReset + #10;
    ImageFree(img);
  end;
end;

function PlaceholderPreview(const name: AnsiString; width, height: Integer): AnsiString;
var i: Integer; labelText: AnsiString;
begin
  labelText := '[ ' + UpperCase(Copy(name, Length(name) - 2, 3)) + ' ]';
  Result := '';
  for i := 1 to height do
  begin
    if i = (height div 2) + 1 then
      Result := Result + AnsiColor(36, Fit(labelText, width)) + #10
    else
      Result := Result + AnsiColor(90, Fit('', width)) + #10;
  end;
end;

function EntryLine(pane, idx, width: Integer): AnsiString;
var
  prefix, mark, sizeText: AnsiString;
  nameWidth: Integer;
begin
  if idx >= ListLen(pane) then
  begin
    Result := Fit('', width);
    Exit;
  end;
  if idx = Selected[pane] then mark := '>' else mark := ' ';
  if EntryIsDir(pane, idx) then prefix := mark + '[D] ' else prefix := mark + '    ';
  if EntryIsDir(pane, idx) or (EntrySize(pane, idx) < 0) then
    sizeText := ''
  else
    sizeText := IntToStr(EntrySize(pane, idx));
  nameWidth := width - 12;
  if nameWidth < 8 then nameWidth := width;
  if nameWidth = width then
    Result := Fit(prefix + EntryName(pane, idx), width)
  else
    Result := Fit(prefix + EntryName(pane, idx), nameWidth) + ' ' + Fit(sizeText, 10);
end;

function PreviewFor(pane, idx, width, height: Integer): AnsiString;
var full, name: AnsiString;
begin
  name := EntryName(pane, idx);
  if EntryIsDir(pane, idx) then
  begin
    Result := PlaceholderPreview(name, width, height);
    Exit;
  end;

  full := JoinPath(Paths[pane], name);
  if HasSuffix(name, '.png') then
    Result := PngPreview(full, width, height)
  else if HasSuffix(name, '.pas') or HasSuffix(name, '.txt') or
          HasSuffix(name, '.md') or HasSuffix(name, '.c') or
          HasSuffix(name, '.h') then
    Result := TextPreview(full, width, height)
  else
    Result := PlaceholderPreview(name, width, height);
end;

procedure LoadPane(p: Integer);
var ok: Boolean;
begin
  if p = 0 then ok := GetDirectoryContents(Paths[p], List0)
  else if p = 1 then ok := GetDirectoryContents(Paths[p], List1)
  else if p = 2 then ok := GetDirectoryContents(Paths[p], List2)
  else ok := GetDirectoryContents(Paths[p], List3);
  if not ok then
  begin
    if p = 0 then SetLength(List0, 0)
    else if p = 1 then SetLength(List1, 0)
    else if p = 2 then SetLength(List2, 0)
    else SetLength(List3, 0);
  end;
  if Selected[p] < 0 then Selected[p] := 0;
  if (ListLen(p) > 0) and (Selected[p] >= ListLen(p)) then
    Selected[p] := ListLen(p) - 1;
end;

procedure RenderCompactRow(row, paneWidth: Integer);
var p: Integer; s: AnsiString;
begin
  for p := 0 to PaneCount - 1 do
  begin
    s := EntryLine(p, row, paneWidth);
    if p = FocusPane then s := AnsiBold + s + AnsiReset;
    write(s);
    if p < PaneCount - 1 then write(' ');
  end;
  writeln;
end;

procedure RenderTilePane(p, paneWidth, previewHeight: Integer);
var idx: Integer; s, name: AnsiString;
begin
  writeln(AnsiBold + Fit(Paths[p], paneWidth) + AnsiReset);
  if ListLen(p) = 0 then
  begin
    writeln(Fit('(empty or unreadable)', paneWidth));
    Exit;
  end;
  idx := Selected[p];
  writeln(EntryLine(p, idx, paneWidth));
  s := PreviewFor(p, idx, paneWidth, previewHeight);
  if s = '' then
  begin
    name := EntryName(p, idx);
    s := PlaceholderPreview(name, paneWidth, previewHeight);
  end;
  write(s);
  writeln(IntToStr(ListLen(p)) + ' entries');
end;

procedure RenderFrame;
var
  cols, rows, paneWidth, shown, p, i: Integer;
begin
  if not TerminalSize(cols, rows) then
  begin
    cols := 100;
    rows := 28;
  end;
  if cols < 40 then cols := 40;
  paneWidth := (cols - (PaneCount - 1)) div PaneCount;
  if paneWidth < 18 then paneWidth := 18;

  write(AnsiClear);
  if ViewMode = VIEW_COMPACT then
  begin
    for p := 0 to PaneCount - 1 do
    begin
      if p = FocusPane then
        write(AnsiBold + Fit(Paths[p], paneWidth) + AnsiReset)
      else
        write(Fit(Paths[p], paneWidth));
      if p < PaneCount - 1 then write(' ');
    end;
    writeln;
    shown := rows - 4;
    if shown < 1 then shown := 1;
    for i := 0 to shown - 1 do RenderCompactRow(i, paneWidth);
  end
  else
  begin
    for p := 0 to PaneCount - 1 do
    begin
      RenderTilePane(p, paneWidth, 10);
      if p < PaneCount - 1 then writeln;
    end;
  end;
  writeln('1-4 panes  Tab focus  j/k select  o open  u up  t tile/compact  q quit');
end;

procedure OpenSelected;
var idx: Integer; name: AnsiString;
begin
  idx := Selected[FocusPane];
  if (idx >= 0) and (idx < ListLen(FocusPane)) and EntryIsDir(FocusPane, idx) then
  begin
    name := EntryName(FocusPane, idx);
    Paths[FocusPane] := JoinPath(Paths[FocusPane], name);
    Selected[FocusPane] := 0;
    LoadPane(FocusPane);
  end;
end;

procedure HandleKey(ch: Char; var done: Boolean);
begin
  if ch = #0 then Exit;
  if ch = 'q' then done := True
  else if ch = 't' then
  begin
    if ViewMode = VIEW_COMPACT then ViewMode := VIEW_TILE else ViewMode := VIEW_COMPACT;
  end
  else if ch = #9 then
    FocusPane := (FocusPane + 1) mod PaneCount
  else if (ch >= '1') and (ch <= '4') then
  begin
    PaneCount := Ord(ch) - Ord('0');
    if FocusPane >= PaneCount then FocusPane := PaneCount - 1;
  end
  else if ch = 'j' then
  begin
    if Selected[FocusPane] < ListLen(FocusPane) - 1 then
      Selected[FocusPane] := Selected[FocusPane] + 1;
  end
  else if ch = 'k' then
  begin
    if Selected[FocusPane] > 0 then
      Selected[FocusPane] := Selected[FocusPane] - 1;
  end
  else if ch = 'o' then
    OpenSelected
  else if ch = 'u' then
  begin
    Paths[FocusPane] := ParentPath(Paths[FocusPane]);
    Selected[FocusPane] := 0;
    LoadPane(FocusPane);
  end;
end;

procedure ParseArgs;
var i, pathIdx: Integer; a: AnsiString;
begin
  PaneCount := 1;
  FocusPane := 0;
  ViewMode := VIEW_COMPACT;
  Interactive := False;
  for i := 0 to MAX_PANES - 1 do
  begin
    Paths[i] := '.';
    Selected[i] := 0;
  end;

  pathIdx := 0;
  for i := 1 to ParamCount do
  begin
    a := ParamStr(i);
    if a = '--tile' then ViewMode := VIEW_TILE
    else if a = '--compact' then ViewMode := VIEW_COMPACT
    else if a = '--interactive' then Interactive := True
    else if a = '--panes=1' then PaneCount := 1
    else if a = '--panes=2' then PaneCount := 2
    else if a = '--panes=3' then PaneCount := 3
    else if a = '--panes=4' then PaneCount := 4
    else if pathIdx < MAX_PANES then
    begin
      Paths[pathIdx] := a;
      pathIdx := pathIdx + 1;
      if PaneCount < pathIdx then PaneCount := pathIdx;
    end;
  end;
end;

var
  p: Integer;
  done: Boolean;
  ch: Char;
begin
  ParseArgs;
  for p := 0 to MAX_PANES - 1 do LoadPane(p);
  RenderFrame;

  if Interactive then
  begin
    done := False;
    AnsiSetRawMode(True);
    while not done do
    begin
      ch := AnsiReadKey;
      if ch <> #0 then
      begin
        HandleKey(ch, done);
        RenderFrame;
      end;
    end;
    AnsiSetRawMode(False);
  end;
end.
