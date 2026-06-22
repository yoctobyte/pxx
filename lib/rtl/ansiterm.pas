unit ansiterm;

interface

function AnsiColor(fg: Integer; const s: AnsiString): AnsiString;
function AnsiRGB(fgR, fgG, fgB: Integer; const s: AnsiString): AnsiString;
function AnsiBgRGB(r, g, b: Integer): AnsiString;
function AnsiReset: AnsiString;
function AnsiBold: AnsiString;
function AnsiClear: AnsiString;
function AnsiMove(row, col: Integer): AnsiString;

{ Backend primitives the screen manager (unit `screen`) drives. Colour setters
  here SET the pen (no string wrap, no auto-reset), unlike AnsiColor/AnsiRGB. }
function AnsiSetFg(code: Integer): AnsiString;   { SGR 30..37 / 90..97 }
function AnsiSetBg(code: Integer): AnsiString;   { SGR 40..47 / 100..107 }
function AnsiHideCursor: AnsiString;
function AnsiShowCursor: AnsiString;
function AnsiAltScreen(enable: Boolean): AnsiString;

function TerminalSize(var cols, rows: Integer): Boolean;
procedure AnsiSetRawMode(enable: Boolean);
function AnsiReadKey: Char;
{ Unbuffered write of s to stdout (raw syscall) — a TUI must not wait on Pascal's
  output buffering to flush, so the screen manager renders through this. }
procedure AnsiWrite(const s: AnsiString);

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

function AnsiSetFg(code: Integer): AnsiString;
begin
  Result := '' + ESC + '[' + IntToStr(code) + 'm';
end;

function AnsiSetBg(code: Integer): AnsiString;
begin
  Result := '' + ESC + '[' + IntToStr(code) + 'm';
end;

function AnsiHideCursor: AnsiString;
begin
  Result := '' + ESC + '[?25l';
end;

function AnsiShowCursor: AnsiString;
begin
  Result := '' + ESC + '[?25h';
end;

function AnsiAltScreen(enable: Boolean): AnsiString;
begin
  if enable then
    Result := '' + ESC + '[?1049h'
  else
    Result := '' + ESC + '[?1049l';
end;

function GetSysIoctl: Integer;
begin
  Result := -1;
  {$ifdef CPU_I386}
    Result := 54;
  {$endif}
  {$ifdef CPU_AARCH64}
    Result := 29;
  {$endif}
  {$ifdef CPU_ARM32}
    Result := 54;
  {$endif}
  {$ifdef CPUX86_64}
    Result := 16;
  {$endif}
end;

function GetSysRead: Integer;
begin
  Result := -1;
  {$ifdef CPU_I386}
    Result := 3;
  {$endif}
  {$ifdef CPU_AARCH64}
    Result := 63;
  {$endif}
  {$ifdef CPU_ARM32}
    Result := 3;
  {$endif}
  {$ifdef CPUX86_64}
    Result := 0;
  {$endif}
end;

function GetSysFcntl: Integer;
begin
  Result := -1;
  {$ifdef CPU_I386}
    Result := 55;
  {$endif}
  {$ifdef CPU_AARCH64}
    Result := 25;
  {$endif}
  {$ifdef CPU_ARM32}
    Result := 55;
  {$endif}
  {$ifdef CPUX86_64}
    Result := 72;
  {$endif}
end;

function GetSysWrite: Integer;
begin
  Result := -1;
  {$ifdef CPU_I386}
    Result := 4;
  {$endif}
  {$ifdef CPU_AARCH64}
    Result := 64;
  {$endif}
  {$ifdef CPU_ARM32}
    Result := 4;
  {$endif}
  {$ifdef CPUX86_64}
    Result := 1;
  {$endif}
end;

procedure AnsiWrite(const s: AnsiString);
var w: Integer; res: Int64;
begin
  if Length(s) = 0 then Exit;
  w := GetSysWrite;
  if w = -1 then Exit;
  res := __pxxrawsyscall(w, 1, Int64(@s[1]), Length(s), 0, 0, 0);   { fd 1 = stdout }
end;

type
  TTermios = record
    IFlag: LongWord;
    OFlag: LongWord;
    CFlag: LongWord;
    LFlag: LongWord;
    Line: Byte;
    CC: array[0..31] of Byte;
    ISpeed: LongWord;
    OSpeed: LongWord;
  end;

var
  OrigTermios: TTermios;
  RawModeEnabled: Boolean = False;

procedure AnsiSetRawMode(enable: Boolean);
var
  sysIoctlVal: Integer;
  t: TTermios;
  res: Int64;
begin
  sysIoctlVal := GetSysIoctl;
  if sysIoctlVal = -1 then Exit;

  if enable then
  begin
    if RawModeEnabled then Exit;
    { Read current state }
    res := __pxxrawsyscall(sysIoctlVal, 0, $5401, Int64(@OrigTermios), 0, 0, 0); { TCGETS }
    if res = 0 then
    begin
      t := OrigTermios;
      t.LFlag := t.LFlag and (not LongWord($00000002)); { ICANON }
      t.LFlag := t.LFlag and (not LongWord($00000008)); { ECHO }
      t.CC[6] := 1; { VMIN }
      t.CC[5] := 0; { VTIME }
      res := __pxxrawsyscall(sysIoctlVal, 0, $5402, Int64(@t), 0, 0, 0); { TCSETS }
      if res = 0 then
        RawModeEnabled := True;
    end;
  end
  else
  begin
    if not RawModeEnabled then Exit;
    res := __pxxrawsyscall(sysIoctlVal, 0, $5402, Int64(@OrigTermios), 0, 0, 0); { TCSETS }
    if res = 0 then
      RawModeEnabled := False;
  end;
end;

function AnsiReadKey: Char;
var
  c: Char;
  res: Int64;
  sysFcntlVal, sysReadVal: Integer;
  flags: Int64;
begin
  sysFcntlVal := GetSysFcntl;
  sysReadVal := GetSysRead;
  c := #0;
  if (sysFcntlVal = -1) or (sysReadVal = -1) then
  begin
    Result := #0;
    Exit;
  end;

  { Temporarily set stdin to non-blocking }
  flags := __pxxrawsyscall(sysFcntlVal, 0, 3, 0, 0, 0, 0); { F_GETFL }
  res := __pxxrawsyscall(sysFcntlVal, 0, 4, flags or $800, 0, 0, 0); { F_SETFL, O_NONBLOCK }

  res := __pxxrawsyscall(sysReadVal, 0, Int64(@c), 1, 0, 0, 0);

  { Restore stdin flags }
  res := __pxxrawsyscall(sysFcntlVal, 0, 4, flags, 0, 0, 0);

  if res = 1 then
    Result := c
  else
    Result := #0;
end;

function TerminalSize(var cols, rows: Integer): Boolean;
type
  TWinSize = record
    Row, Col, XPixel, YPixel: Word;
  end;
var
  ws: TWinSize;
  res: Int64;
  sysIoctlVal: Integer;
begin
  cols := 80;
  rows := 24;
  Result := False;

  sysIoctlVal := GetSysIoctl;
  if sysIoctlVal <> -1 then
  begin
    ws.Row := 0;
    ws.Col := 0;
    res := __pxxrawsyscall(sysIoctlVal, 1, $5413, Int64(@ws), 0, 0, 0);
    if (res = 0) and (ws.Col > 0) and (ws.Row > 0) then
    begin
      cols := ws.Col;
      rows := ws.Row;
      Result := True;
    end;
  end;
end;

end.
