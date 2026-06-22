unit screen;
{ A small ncurses-style screen MANAGER over ansiterm (which stays the low-level
  escape/tty backend). You draw into an off-screen "back" buffer of cells; the
  manager keeps a "front" buffer mirroring what is physically on the terminal,
  and ScreenRender emits the MINIMAL escape sequence to reconcile them — a cursor
  move only when the next changed cell is not where the cursor already is, and an
  SGR pen change only when colour/attr actually change. No full repaints, no
  flicker.

  Single global screen (stdscr-style), held as parallel arrays (char / fg / bg /
  attr) rather than a record with dynamic-array fields. Render is split from the
  terminal write so the diff is exact-byte testable without a real terminal. }

interface

uses ansiterm, sysutils;

const
  COLOR_DEFAULT = -1;             { use the terminal's default colour }

  ATTR_NONE      = 0;
  ATTR_BOLD      = 1;
  ATTR_DIM       = 2;
  ATTR_UNDERLINE = 4;
  ATTR_REVERSE   = 8;

{ Allocate a cols x rows screen. The front buffer is primed to a state that
  differs from every back cell, so the first ScreenRender paints everything. }
procedure ScreenInitSize(cols, rows: Integer);
{ Query the real terminal size and ScreenInitSize to it (min 1x1). }
procedure ScreenInit;

function ScreenCols: Integer;
function ScreenRows: Integer;

{ Drawing — these touch only the back buffer. }
procedure ScreenSetPen(fg, bg, attr: Integer);
procedure ScreenClear;                                   { blank with current pen }
procedure ScreenPutChar(x, y: Integer; ch: Char);
procedure ScreenWrite(x, y: Integer; const s: AnsiString);
procedure ScreenBox(x, y, w, h: Integer);                { ASCII border }

{ Compute the minimal escape string to bring the terminal from the front buffer
  to the back buffer, and fold back -> front. Pure of terminal I/O. }
function ScreenRender: AnsiString;
{ ScreenRender + write it to stdout. }
procedure ScreenRefresh;

implementation

var
  scCols, scRows: Integer;
  bCh: array of Char;
  bFg, bBg, bAttr: array of Integer;
  fCh: array of Char;
  fFg, fBg, fAttr: array of Integer;
  penFg, penBg, penAttr: Integer;

procedure ScreenInitSize(cols, rows: Integer);
var i, n: Integer;
begin
  if cols < 1 then cols := 1;
  if rows < 1 then rows := 1;
  scCols := cols;
  scRows := rows;
  n := cols * rows;
  SetLength(bCh, n); SetLength(bFg, n); SetLength(bBg, n); SetLength(bAttr, n);
  SetLength(fCh, n); SetLength(fFg, n); SetLength(fBg, n); SetLength(fAttr, n);
  penFg := COLOR_DEFAULT; penBg := COLOR_DEFAULT; penAttr := ATTR_NONE;
  for i := 0 to n - 1 do
  begin
    bCh[i] := ' '; bFg[i] := COLOR_DEFAULT; bBg[i] := COLOR_DEFAULT; bAttr[i] := ATTR_NONE;
    { front primed to an impossible glyph so every cell is initially "dirty" }
    fCh[i] := #1; fFg[i] := -2; fBg[i] := -2; fAttr[i] := -2;
  end;
end;

procedure ScreenInit;
var c, r: Integer;
begin
  c := 80; r := 24;
  TerminalSize(c, r);
  ScreenInitSize(c, r);
end;

function ScreenCols: Integer;
begin
  ScreenCols := scCols;
end;

function ScreenRows: Integer;
begin
  ScreenRows := scRows;
end;

procedure ScreenSetPen(fg, bg, attr: Integer);
begin
  penFg := fg; penBg := bg; penAttr := attr;
end;

procedure ScreenClear;
var i: Integer;
begin
  for i := 0 to scCols * scRows - 1 do
  begin
    bCh[i] := ' '; bFg[i] := penFg; bBg[i] := penBg; bAttr[i] := penAttr;
  end;
end;

procedure ScreenPutChar(x, y: Integer; ch: Char);
var idx: Integer;
begin
  if (x < 0) or (y < 0) or (x >= scCols) or (y >= scRows) then Exit;
  idx := y * scCols + x;
  bCh[idx] := ch; bFg[idx] := penFg; bBg[idx] := penBg; bAttr[idx] := penAttr;
end;

procedure ScreenWrite(x, y: Integer; const s: AnsiString);
var i: Integer;
begin
  for i := 1 to Length(s) do
    ScreenPutChar(x + i - 1, y, s[i]);
end;

procedure ScreenBox(x, y, w, h: Integer);
var i: Integer;
begin
  if (w < 2) or (h < 2) then Exit;
  ScreenPutChar(x, y, '+');
  ScreenPutChar(x + w - 1, y, '+');
  ScreenPutChar(x, y + h - 1, '+');
  ScreenPutChar(x + w - 1, y + h - 1, '+');
  for i := 1 to w - 2 do
  begin
    ScreenPutChar(x + i, y, '-');
    ScreenPutChar(x + i, y + h - 1, '-');
  end;
  for i := 1 to h - 2 do
  begin
    ScreenPutChar(x, y + i, '|');
    ScreenPutChar(x + w - 1, y + i, '|');
  end;
end;

{ Build the SGR pen sequence: reset, then attrs, then colours. Emitted only when
  the pen changes (Render tracks the last one emitted). }
function PenSeq(fg, bg, attr: Integer): AnsiString;
var s: AnsiString;
begin
  s := AnsiReset;
  if (attr and ATTR_BOLD) <> 0 then s := s + AnsiBold;
  if (attr and ATTR_DIM) <> 0 then s := s + '' + #27 + '[2m';
  if (attr and ATTR_UNDERLINE) <> 0 then s := s + '' + #27 + '[4m';
  if (attr and ATTR_REVERSE) <> 0 then s := s + '' + #27 + '[7m';
  if fg <> COLOR_DEFAULT then s := s + AnsiSetFg(fg);
  if bg <> COLOR_DEFAULT then s := s + AnsiSetBg(bg);
  PenSeq := s;
end;

function ScreenRender: AnsiString;
var
  x, y, idx: Integer;
  outp: AnsiString;
  lastFg, lastBg, lastAttr: Integer;
  curRow, curCol: Integer;
  dirty: Boolean;
begin
  outp := '';
  curRow := -1; curCol := -1;
  lastFg := -2; lastBg := -2; lastAttr := -2;   { force first pen emit }
  for y := 0 to scRows - 1 do
    for x := 0 to scCols - 1 do
    begin
      idx := y * scCols + x;
      dirty := (bCh[idx] <> fCh[idx]) or (bFg[idx] <> fFg[idx]) or
               (bBg[idx] <> fBg[idx]) or (bAttr[idx] <> fAttr[idx]);
      if dirty then
      begin
        if (curRow <> y) or (curCol <> x) then
        begin
          outp := outp + AnsiMove(y + 1, x + 1);   { terminal is 1-based }
          curRow := y; curCol := x;
        end;
        if (bFg[idx] <> lastFg) or (bBg[idx] <> lastBg) or (bAttr[idx] <> lastAttr) then
        begin
          outp := outp + PenSeq(bFg[idx], bBg[idx], bAttr[idx]);
          lastFg := bFg[idx]; lastBg := bBg[idx]; lastAttr := bAttr[idx];
        end;
        outp := outp + bCh[idx];
        curCol := curCol + 1;            { a printed glyph advances the cursor }
        if curCol >= scCols then curCol := -1;   { past the edge: position now unknown }
        fCh[idx] := bCh[idx]; fFg[idx] := bFg[idx]; fBg[idx] := bBg[idx]; fAttr[idx] := bAttr[idx];
      end;
    end;
  ScreenRender := outp;
end;

procedure ScreenRefresh;
begin
  Write(ScreenRender);
end;

end.
