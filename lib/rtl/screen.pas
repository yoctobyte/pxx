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
  { Colour indices 0..15 (ncurses-style), used for both fg and bg; the manager
    maps them to the right SGR code (30+/40+ normal, 90+/100+ bright). }
  COLOR_BLACK   = 0;
  COLOR_RED     = 1;
  COLOR_GREEN   = 2;
  COLOR_YELLOW  = 3;
  COLOR_BLUE    = 4;
  COLOR_MAGENTA = 5;
  COLOR_CYAN    = 6;
  COLOR_WHITE   = 7;
  COLOR_BRIGHT_BLACK   = 8;
  COLOR_BRIGHT_RED     = 9;
  COLOR_BRIGHT_GREEN   = 10;
  COLOR_BRIGHT_YELLOW  = 11;
  COLOR_BRIGHT_BLUE    = 12;
  COLOR_BRIGHT_MAGENTA = 13;
  COLOR_BRIGHT_CYAN    = 14;
  COLOR_BRIGHT_WHITE   = 15;

  ATTR_NONE      = 0;
  ATTR_BOLD      = 1;
  ATTR_DIM       = 2;
  ATTR_UNDERLINE = 4;
  ATTR_REVERSE   = 8;

  { Key codes from ScreenReadKey / ScreenDecodeKey. Plain bytes come back as
    their ordinal (0..255, so Enter=13, Tab=9, Backspace=127); the codes below
    (>255) are the non-byte keys. }
  KEY_NONE    = -1;               { no key available (non-blocking read) }
  KEY_UNKNOWN = 1000;
  KEY_UP      = 1001;
  KEY_DOWN    = 1002;
  KEY_RIGHT   = 1003;
  KEY_LEFT    = 1004;
  KEY_HOME    = 1005;
  KEY_END     = 1006;
  KEY_PGUP    = 1007;
  KEY_PGDN    = 1008;
  KEY_INS     = 1009;
  KEY_DEL     = 1010;
  KEY_ESC     = 1011;

{ Allocate a cols x rows screen. The front buffer is primed to a state that
  differs from every back cell, so the first ScreenRender paints everything. }
procedure ScreenInitSize(cols, rows: Integer);
{ Query the real terminal size and ScreenInitSize to it (min 1x1). }
procedure ScreenInit;

function ScreenCols: Integer;
function ScreenRows: Integer;
{ Back-buffer glyphs of row y as plain text (no attributes) — for tests, layout
  checks, and serialization. }
function ScreenDumpRow(y: Integer): AnsiString;

{ Clipping / origin: after ScreenSetClip(x,y,w,h) all draw coordinates are
  relative to (x,y) and clipped to the w x h region — the basis for panels/
  layout. ScreenResetClip restores the full screen. }
procedure ScreenSetClip(x, y, w, h: Integer);
procedure ScreenResetClip;

{ Drawing — these touch only the back buffer, through the current clip. }
procedure ScreenSetPen(fg, bg, attr: Integer);
procedure ScreenClear;                                   { blank with current pen }
procedure ScreenPutChar(x, y: Integer; ch: Char);
procedure ScreenWrite(x, y: Integer; const s: AnsiString);
procedure ScreenBox(x, y, w, h: Integer);                { ASCII border }
procedure ScreenHLine(x, y, len: Integer; ch: Char);
procedure ScreenVLine(x, y, len: Integer; ch: Char);
procedure ScreenFillRect(x, y, w, h: Integer; ch: Char);

{ Enter/leave full-screen mode (raw mode + xterm alternate buffer + cursor
  hidden, then a blank paint). ScreenStart sizes to the real terminal; ScreenEnd
  restores it. They touch the real tty, so they are not part of the byte-exact
  test (which drives Render/decoder directly). }
procedure ScreenStart;
procedure ScreenEnd;

{ Compute the minimal escape string to bring the terminal from the front buffer
  to the back buffer, and fold back -> front. Pure of terminal I/O. }
function ScreenRender: AnsiString;
{ ScreenRender + write it to stdout. }
procedure ScreenRefresh;

{ --- input --- }
{ Decode a key/escape sequence (ESC[A, ESC[3~, ESCOA, a plain byte, ...) into a
  byte ordinal or a KEY_* constant. Pure — testable without a terminal. }
function ScreenDecodeKey(const seq: AnsiString): Integer;
{ Read one key event from stdin (raw mode assumed): a plain byte's ordinal, a
  KEY_* constant for an escape sequence, or KEY_NONE when nothing is waiting
  (non-blocking — for polling). }
function ScreenReadKey: Integer;
{ Like ScreenReadKey but BLOCKS for the first byte — the call to use in an event
  loop so it waits for input instead of busy-spinning. Returns KEY_NONE only on
  EOF/error. }
function ScreenWaitKey: Integer;

implementation

var
  scCols, scRows: Integer;
  bCh: array of Char;
  bFg, bBg, bAttr: array of Integer;
  fCh: array of Char;
  fFg, fBg, fAttr: array of Integer;
  penFg, penBg, penAttr: Integer;
  clipX, clipY, clipW, clipH: Integer;   { draw origin + clip region }

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
  clipX := 0; clipY := 0; clipW := cols; clipH := rows;
  for i := 0 to n - 1 do
  begin
    bCh[i] := ' '; bFg[i] := COLOR_DEFAULT; bBg[i] := COLOR_DEFAULT; bAttr[i] := ATTR_NONE;
    { front primed to an impossible glyph so every cell is initially "dirty" }
    fCh[i] := #1; fFg[i] := -2; fBg[i] := -2; fAttr[i] := -2;
  end;
end;

procedure ScreenSetClip(x, y, w, h: Integer);
begin
  clipX := x; clipY := y; clipW := w; clipH := h;
end;

procedure ScreenResetClip;
begin
  clipX := 0; clipY := 0; clipW := scCols; clipH := scRows;
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

function ScreenDumpRow(y: Integer): AnsiString;
var x: Integer; s: AnsiString;
begin
  s := '';
  if (y >= 0) and (y < scRows) then
    for x := 0 to scCols - 1 do s := s + bCh[y * scCols + x];
  ScreenDumpRow := s;
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
var gx, gy, idx: Integer;
begin
  { x,y are clip-local: reject outside the clip region, then translate. }
  if (x < 0) or (y < 0) or (x >= clipW) or (y >= clipH) then Exit;
  gx := clipX + x; gy := clipY + y;
  if (gx < 0) or (gy < 0) or (gx >= scCols) or (gy >= scRows) then Exit;
  idx := gy * scCols + gx;
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

{ Map a 0..15 colour index to its SGR code (30/90 for fg, 40/100 for bg). }
function FgCode(c: Integer): Integer;
begin
  if c >= 8 then FgCode := 90 + (c - 8) else FgCode := 30 + c;
end;

function BgCode(c: Integer): Integer;
begin
  if c >= 8 then BgCode := 100 + (c - 8) else BgCode := 40 + c;
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
  if fg <> COLOR_DEFAULT then s := s + AnsiSetFg(FgCode(fg));
  if bg <> COLOR_DEFAULT then s := s + AnsiSetBg(BgCode(bg));
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

procedure ScreenHLine(x, y, len: Integer; ch: Char);
var i: Integer;
begin
  for i := 0 to len - 1 do ScreenPutChar(x + i, y, ch);
end;

procedure ScreenVLine(x, y, len: Integer; ch: Char);
var i: Integer;
begin
  for i := 0 to len - 1 do ScreenPutChar(x, y + i, ch);
end;

procedure ScreenFillRect(x, y, w, h: Integer; ch: Char);
var j: Integer;
begin
  for j := 0 to h - 1 do ScreenHLine(x, y + j, w, ch);
end;

procedure ScreenRefresh;
begin
  AnsiWrite(ScreenRender);
end;

procedure ScreenStart;
begin
  AnsiSetRawMode(True);
  AnsiWrite(AnsiAltScreen(True));
  AnsiWrite(AnsiHideCursor);
  ScreenInit;          { size to the real terminal + alloc buffers }
  ScreenClear;
  ScreenRefresh;       { blank the alternate screen }
end;

procedure ScreenEnd;
begin
  AnsiWrite(AnsiShowCursor);
  AnsiWrite(AnsiAltScreen(False));
  AnsiSetRawMode(False);
end;

function ScreenDecodeKey(const seq: AnsiString): Integer;
var n, num, i: Integer; lastc: Char;
begin
  n := Length(seq);
  if n = 0 then
  begin
    ScreenDecodeKey := KEY_UNKNOWN;
    Exit;
  end;
  if n = 1 then
  begin
    if seq[1] = #27 then ScreenDecodeKey := KEY_ESC
    else ScreenDecodeKey := Ord(seq[1]);   { plain byte: Enter=13, Tab=9, BS=127 }
    Exit;
  end;
  { multi-byte must be a CSI (ESC[) or SS3 (ESCO) sequence }
  if (seq[1] <> #27) or ((seq[2] <> '[') and (seq[2] <> 'O')) then
  begin
    ScreenDecodeKey := KEY_UNKNOWN;
    Exit;
  end;
  lastc := seq[n];
  if lastc = 'A' then ScreenDecodeKey := KEY_UP
  else if lastc = 'B' then ScreenDecodeKey := KEY_DOWN
  else if lastc = 'C' then ScreenDecodeKey := KEY_RIGHT
  else if lastc = 'D' then ScreenDecodeKey := KEY_LEFT
  else if lastc = 'H' then ScreenDecodeKey := KEY_HOME
  else if lastc = 'F' then ScreenDecodeKey := KEY_END
  else if lastc = '~' then
  begin
    num := 0;
    for i := 3 to n - 1 do
      if (seq[i] >= '0') and (seq[i] <= '9') then num := num * 10 + (Ord(seq[i]) - Ord('0'));
    if (num = 1) or (num = 7) then ScreenDecodeKey := KEY_HOME
    else if (num = 4) or (num = 8) then ScreenDecodeKey := KEY_END
    else if num = 2 then ScreenDecodeKey := KEY_INS
    else if num = 3 then ScreenDecodeKey := KEY_DEL
    else if num = 5 then ScreenDecodeKey := KEY_PGUP
    else if num = 6 then ScreenDecodeKey := KEY_PGDN
    else ScreenDecodeKey := KEY_UNKNOWN;
  end
  else
    ScreenDecodeKey := KEY_UNKNOWN;
end;

{ ESC has just been consumed: gather the rest of the escape sequence, bounded —
  a CSI (ESC[) / SS3 (ESCO) sequence ends at its final byte (0x40..0x7E), so we
  stop there instead of slurping whatever else is buffered (which would eat the
  next keypress). A lone ESC, or ESC+char (Alt-key), reads at most one more. }
function ReadEscRest: AnsiString;
var seq: AnsiString; b: Char; bo: Integer; done: Boolean;
begin
  seq := '' + #27;
  b := AnsiReadKey;
  if b <> #0 then
  begin
    seq := seq + b;
    if (b = '[') or (b = 'O') then
    begin
      done := False;
      while not done do
      begin
        b := AnsiReadKey;
        if b = #0 then
          done := True
        else
        begin
          seq := seq + b;
          bo := Ord(b);
          if (bo >= 64) and (bo <= 126) then done := True;   { CSI/SS3 final byte }
        end;
      end;
    end;
  end;
  ReadEscRest := seq;
end;

function ScreenReadKey: Integer;
var c: Char;
begin
  c := AnsiReadKey;
  if c = #0 then ScreenReadKey := KEY_NONE
  else if c <> #27 then ScreenReadKey := Ord(c)
  else ScreenReadKey := ScreenDecodeKey(ReadEscRest);
end;

function ScreenWaitKey: Integer;
var c: Char;
begin
  c := AnsiReadKeyWait;          { block until the first byte }
  if c = #0 then ScreenWaitKey := KEY_NONE
  else if c <> #27 then ScreenWaitKey := Ord(c)
  else ScreenWaitKey := ScreenDecodeKey(ReadEscRest);
end;

end.
