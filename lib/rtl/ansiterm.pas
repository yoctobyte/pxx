unit ansiterm;

interface

function AnsiColor(fg: Integer; const s: AnsiString): AnsiString;
function AnsiRGB(fgR, fgG, fgB: Integer; const s: AnsiString): AnsiString;
function AnsiBgRGB(r, g, b: Integer): AnsiString;
function AnsiReset: AnsiString;
function AnsiBold: AnsiString;
function AnsiClear: AnsiString;
function AnsiMove(row, col: Integer): AnsiString;
function TerminalSize(var cols, rows: Integer): Boolean;

implementation

uses sysutils;

const
  ESC = #27;

function AnsiColor(fg: Integer; const s: AnsiString): AnsiString;
begin
  Result := '' + ESC + '[' + IntToStr(fg) + 'm' + s + ESC + '[0m';
end;

function AnsiRGB(fgR, fgG, fgB: Integer; const s: AnsiString): AnsiString;
begin
  Result := '' + ESC + '[38;2;' + IntToStr(fgR) + ';' + IntToStr(fgG) + ';' + IntToStr(fgB) + 'm' + s + ESC + '[0m';
end;

function AnsiBgRGB(r, g, b: Integer): AnsiString;
begin
  Result := '' + ESC + '[48;2;' + IntToStr(r) + ';' + IntToStr(g) + ';' + IntToStr(b) + 'm';
end;

function AnsiReset: AnsiString;
begin
  Result := '' + ESC + '[0m';
end;

// Note: ESC is a Char, prefixing with '' ensures it is concatenated as a string.
function AnsiBold: AnsiString;
begin
  Result := '' + ESC + '[1m';
end;

function AnsiClear: AnsiString;
begin
  Result := '' + ESC + '[2J' + ESC + '[H';
end;

function AnsiMove(row, col: Integer): AnsiString;
begin
  Result := '' + ESC + '[' + IntToStr(row) + ';' + IntToStr(col) + 'H';
end;

function TerminalSize(var cols, rows: Integer): Boolean;
type
  TWinSize = record
    Row, Col, XPixel, YPixel: Word;
  end;
var
  ws: TWinSize;
  res: Int64;
  sysIoctl: Integer;
begin
  cols := 80;
  rows := 24;
  Result := False;

  sysIoctl := -1;
  {$ifdef CPUCPUX86_64}
    sysIoctl := 16;
  {$endif}
  {$ifdef CPU_I386}
    sysIoctl := 54;
  {$endif}
  {$ifdef CPU_AARCH64}
    sysIoctl := 29;
  {$endif}
  {$ifdef CPU_ARM32}
    sysIoctl := 54;
  {$endif}

  // fallback/detect x86_64 macro used in compiler
  {$ifdef CPUX86_64}
    sysIoctl := 16;
  {$endif}

  if sysIoctl <> -1 then
  begin
    ws.Row := 0;
    ws.Col := 0;
    res := __pxxrawsyscall(sysIoctl, 1, $5413, Int64(@ws), 0, 0, 0);
    if (res = 0) and (ws.Col > 0) and (ws.Row > 0) then
    begin
      cols := ws.Col;
      rows := ws.Row;
      Result := True;
    end;
  end;
end;

end.
