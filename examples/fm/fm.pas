program fm;
{ Small terminal file browser demo.

  Usage:
    fm [path]
    fm [left-path] [right-path]

  This first slice is deliberately libc-free and non-interactive: it exercises
  PAL directory scanning through SysUtils and renders one or two terminal panes
  with ANSI strings. File sizes and previews wait for PAL stat/preview helpers. }

uses sysutils, platform, ansiterm;

var
  LeftList, RightList: TFileInfoArray;

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

function EntryLine(const list: TFileInfoArray; idx, width: Integer): AnsiString;
var
  prefix: AnsiString;
begin
  if idx >= Length(list) then
  begin
    Result := Fit('', width);
    Exit;
  end;
  if list[idx].IsDir then
    prefix := '[D] '
  else
    prefix := '    ';
  Result := Fit(prefix + list[idx].Name, width);
end;

procedure RenderSingle(const path: AnsiString; width, rows: Integer);
var
  ok: Boolean;
  i, shown: Integer;
begin
  ok := GetDirectoryContents(path, LeftList);
  writeln(AnsiBold + Fit(path, width) + AnsiReset);
  if not ok then
  begin
    writeln('cannot read directory');
    Exit;
  end;
  shown := rows - 3;
  if shown < 1 then shown := 1;
  for i := 0 to shown - 1 do
    if i < Length(LeftList) then writeln(EntryLine(LeftList, i, width));
  writeln(IntToStr(Length(LeftList)) + ' entries');
end;

procedure RenderDouble(const leftPath, rightPath: AnsiString; width, rows: Integer);
var
  leftOk, rightOk: Boolean;
  i, shown: Integer;
begin
  leftOk := GetDirectoryContents(leftPath, LeftList);
  rightOk := GetDirectoryContents(rightPath, RightList);
  writeln(AnsiBold + Fit(leftPath, width) + AnsiReset + '  ' +
          AnsiBold + Fit(rightPath, width) + AnsiReset);
  shown := rows - 3;
  if shown < 1 then shown := 1;
  for i := 0 to shown - 1 do
    writeln(EntryLine(LeftList, i, width) + '  ' + EntryLine(RightList, i, width));
  if not leftOk then write('left unreadable') else write(IntToStr(Length(LeftList)) + ' entries');
  write('  ');
  if not rightOk then writeln('right unreadable') else writeln(IntToStr(Length(RightList)) + ' entries');
end;

var
  cols, rows, paneWidth: Integer;
  leftPath, rightPath: AnsiString;
begin
  if ParamCount >= 1 then leftPath := ParamStr(1) else leftPath := '.';
  if ParamCount >= 2 then rightPath := ParamStr(2) else rightPath := '';

  if not TerminalSize(cols, rows) then
  begin
    cols := 80;
    rows := 24;
  end;

  if rightPath = '' then
  begin
    write(AnsiClear);
    RenderSingle(leftPath, cols, rows);
  end
  else
  begin
    paneWidth := (cols - 2) div 2;
    if paneWidth < 20 then paneWidth := 20;
    write(AnsiClear);
    RenderDouble(leftPath, rightPath, paneWidth, rows);
  end;
end.
