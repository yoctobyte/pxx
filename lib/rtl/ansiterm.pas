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
begin
  cols := 80;
  rows := 24;
  Result := False;
end;

end.
