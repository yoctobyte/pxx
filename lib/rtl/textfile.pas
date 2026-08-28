{ SPDX-License-Identifier: Zlib }
unit textfile;
{$MODE PXX}   { our dialect; the FPC-parity strict-* flags do not judge this file }
{ Classic text-file primitives on top of PAL byte handles.

  The compiler still treats ReadLn/WriteLn as keywords, so file-handle keyword
  forms need a small compiler hook. This unit provides the underlying RTL
  surface with explicit TextReadLn/TextWriteLn entry points. }

interface

uses platform;

const
  { One page. Big enough that a line-at-a-time read of an ordinary file costs
    one syscall per few dozen lines instead of one per character; small enough
    that `var f: Text` stays a reasonable local. }
  TF_BUFSIZE = 4096;

type
  Text = record
    Handle: Integer;
    Name: AnsiString;
    HitEof: Boolean;
    { Read-ahead buffer. BufPos is the next byte to hand out, BufLen the number
      of valid bytes behind it.

      There is deliberately NO separate one-byte peek slot any more: pushback is
      `Dec(BufPos)`, because the only byte anyone ever pushes back is the one
      TFNextByte just handed over, and it is still sitting right there. The slot
      this replaced was a SECOND lookahead mechanism for the same concept, which
      every reader then had to keep in sync with the first.

      Buffered is False for handles we must not read ahead on — see TFOpened. }
    Buffered: Boolean;
    BufPos: Integer;
    BufLen: Integer;
    Buf: array[0..TF_BUFSIZE - 1] of Byte;
  end;

procedure Assign(var f: Text; const path: AnsiString);
procedure AssignFile(var f: Text; const path: AnsiString);
procedure Reset(var f: Text);
procedure Rewrite(var f: Text);
procedure Append(var f: Text);
procedure Close(var f: Text);
procedure CloseFile(var f: Text);
procedure Erase(var f: Text);
function Eof(var f: Text): Boolean;

{ True when the next character is a line terminator, or at end of file — FPC's
  Eoln, the companion to reading a character at a time. Measured against FPC:

    'ab'#10'c'#10   ->  a b EOLN c EOLN, and EOLN again at end of file
    'a'#13#10'b'#10 ->  a EOLN b EOLN        { CR counts, and Readln eats both }
    'xy'            ->  x y, then EOLN because the file ended

  So CR answers True here even though TextReadChar hands it back as an ordinary
  character — both of those are FPC's behaviour, measured, not inferred from
  each other. Non-destructive: it uses the same one-byte lookahead Eof does, so
  the cursor does not move. }
function Eoln(var f: Text): Boolean;

{ Skip whitespace, then answer "is there nothing left but whitespace?" — the
  loop condition for reading a whitespace-separated table without tripping on
  the blank tail of the last line:

    while not SeekEof(f) do begin Read(f, n); Sum := Sum + n; end;

  Eof is still False while a trailing newline remains, so that same loop
  written with Eof reads one junk value at the end. SeekEof CONSUMES the
  whitespace it skips but never the token after it: the byte that stops the
  scan goes back into the one-slot lookahead, so the next Read sees it. }
function SeekEof(var f: Text): Boolean;

{ Skip blanks, then answer "is the rest of this LINE empty?" — SeekEof's
  companion, and identical to it except that line terminators STOP the scan
  instead of being skipped. So it answers True at the end of a line as well as
  at the end of the file, and leaves the terminator unconsumed for Readln. }
function SeekEoln(var f: Text): Boolean;

{ Rename the assigned file and carry the handle over to the new name, FPC's
  Rename(f, newname). The file must be CLOSED — FPC refuses on an open handle
  and leaves the file alone, and that restriction is copied rather than
  relaxed. After a successful call, Reset(f) opens the NEW name. }
procedure Rename(var f: Text; const NewName: AnsiString);

function IOResult: Integer;

procedure TextWrite(var f: Text; const s: AnsiString);
procedure TextWriteLn(var f: Text; const s: AnsiString);
procedure TextReadLn(var f: Text; var s: AnsiString);

{ One character, FPC's `read(f, c)`. Consumes exactly one byte and leaves the
  cursor on the next, so it interleaves with TextReadLn: `read(f, c)` then
  `readln(f, s)` gives the REST of the line in s. Line endings are characters
  like any other — a character loop over "ab\ncd\n" yields a b #10 c d #10, and
  CR is not swallowed (TextReadLn strips it; this does not, matching FPC on both
  counts). At and past end of file it yields #26, FPC's EOF marker, without
  setting an I/O error. }
procedure TextReadChar(var f: Text; var c: Char);

{ A whitespace-delimited TOKEN, the raw material of FPC's `read(f, number)`.
  Skips leading whitespace INCLUDING line breaks, collects everything up to the
  next whitespace byte or end of file, and pushes that delimiter back so the
  cursor sits immediately after the token — which is what makes `read(t, n)`
  then `readln(t, s)` hand the REST of the line over, and what lets a caller
  ask Eoln afterwards. Measured against FPC 3.2.2, cursor position included
  (the remainder of the file drained character by character after the read):

    '42'#10        -> '42', rest #10          { the terminator is NOT eaten }
    '42 3'#10      -> '42', rest ' 3'#10      { nor is the delimiting space }
    '   42 3'#10   -> '42', rest ' 3'#10
    #10#10'42'#10  -> '42', rest #10          { blank lines are whitespace }
    '42'#13#10     -> '42', rest #13#10       { CR is a delimiter, not eaten }
    '   '#10'  '   -> '',   rest ''           { only whitespace: empty token }

  The caller Vals the token. FPC scans to whitespace too, not to the first
  character a number cannot use: '42,3' is a *runtime error 106* there, not the
  42 a stop-at-any-non-digit reader would give. Ours Vals '42,3', fails, and
  leaves the destination at 0 — a divergence in the ERROR path only, and by the
  project's "language compliance, not error-handling compliance" rule the
  silent 0 stays until I/O checking covers it. Every VALID numeric input agrees. }
procedure TextReadNumTok(var f: Text; var s: AnsiString);

{ Everything up to but NOT over the line terminator — FPC's `read(f, s)` for a
  string, which is a different procedure from `readln(f, s)` however much the
  two spellings look alike. At an end-of-line it returns the empty string and
  does not advance, so repeating it yields '' forever until a `readln` steps
  over the terminator; that is exactly what makes the classic
  `read(f, s); readln(f)` idiom read every line instead of every other one.
  Measured against FPC on the same files as above:

    'L1'#10'L2'#10  -> 'L1', rest #10'L2'#10, and a second read gives ''
    'L1'#13#10      -> 'L1', rest #13#10      { stops AT the CR, keeps it }
    #10'L2'#10      -> '',   rest #10'L2'#10
    'L1'  (no eol)  -> 'L1', rest ''

  TextReadLn keeps its own meaning — read the line AND step over its terminator
  — and stays what `readln(f, s)` lowers to. }
procedure TextReadStrTo(var f: Text; var s: AnsiString);

{ FPC System surface: the standard Input/Output text files and Flush.
  PXX text writes go straight to the fd (no RTL-side buffer), so Flush only
  has to exist and accept the file — there is nothing to drain. }
procedure Flush(var f: Text);
procedure PXXIoCheck;

var
  Input: Text;
  Output: Text;

implementation

const
  TF_OK = 0;

var
  LastIOResult: Integer;

{ {$I+} call-site check: raise (via the sysutils hook) or halt with the IO
  code when the LAST Text operation failed. The compiler sequences a call to
  this after each Text-I/O statement inside a {$I+} region
  (feature-pascal-io-checks-i-plus). Reading clears, like IOResult. }
procedure PXXIoCheck;
var code: Integer;
begin
  code := LastIOResult;
  if code = 0 then Exit;
  LastIOResult := 0;
  if PXXIoErrorHook <> nil then PXXIoErrorHook();
  writeln('Runtime error ', code, ' (I/O error)');
  Halt(code);
end;

const
  { FPC's codes for the two states that are not errnos at all. Measured:
    renaming an OPEN handle answers 102 on fpc 3.2.2. }
  TF_ERR_NOT_ASSIGNED = 102;
  TF_ERR_NOT_OPEN     = 103;

{ A POSITIVE errno -> the code FPC's IOResult reports. MEASURED against fpc
  3.2.2 by producing each condition and reading IOResult back, because FPC does
  NOT simply translate: it maps a known set and passes everything else through
  as the positive errno.

    errno                     FPC IOResult
    2  ENOENT                 2
    36 ENAMETOOLONG           2      <- mapped, not passthrough (36 <> 2)
    13 EACCES                 5
    20 ENOTDIR                5
    21 EISDIR                 5
    40 ELOOP                  40     <- PASSTHROUGH: FPC leaves it alone

  ELOOP is the row that settles the design. Had FPC translated everything, an
  unmapped errno would need a code invented for it, and an invented code is a
  plausible wrong answer with no failure mode that reveals it. It does not, so
  the `else` here is FPC's own behaviour rather than a fallback of ours.

  The mapped rows are exactly the ones measured. Others that look like they
  belong (EPERM, EROFS) are deliberately NOT listed: they could not be produced
  on this box without root, so listing them would be transcription. They take
  the passthrough path, which may differ from FPC -- an unverified guess in the
  table would be worse, because it would look measured. }
function ErrnoToIOResult(e: Integer): Integer;
begin
  case e of
    2, 36: Result := 2;
    13, 20, 21: Result := 5;
  else
    Result := e;
  end;
end;

{ The one place a raw errno becomes a public IOResult. Negative in, FPC's
  numbering out -- so no caller has to know, and no call site can forget.
  Non-negative values are already final codes (TF_OK, TF_ERR_NOT_OPEN...) and
  pass straight through. }
procedure SetIO(code: Integer);
begin
  if code < 0 then
    LastIOResult := ErrnoToIOResult(-code)
  else
    LastIOResult := code;
end;

{ Every reader in this unit goes through the buffer below — there is no second
  place a byte can be hiding, which is the property the old one-byte peek slot
  cost us: it was a parked lookahead that each reader had to remember to drain
  before touching the fd, or they would disagree about where the cursor was.

  TextReadLn still carries its own copy of the loop, and still for its original
  reason: it is the one reader that must NOT set LastIOResult when it succeeds,
  because folding it in would clear a stale I/O code a {$I+} region's
  PXXIoCheck can still see. That distinction now lives in TFFillEx's `quiet`
  flag rather than in a duplicated read — same contract, one mechanism. }
{ Drop whatever is buffered. Called wherever the cursor moves for a reason the
  buffer cannot see (a fresh Assign, a Reset, a Close). }
procedure TFResetBuf(var f: Text);
begin
  f.BufPos := 0;
  f.BufLen := 0;
end;

{ Decide whether this handle may be read ahead on, and start it empty. Only a
  SEEKABLE handle qualifies, for two reasons that happen to coincide: a pipe or
  a terminal cannot be rewound, so Close could not hand the descriptor back
  where the caller left it; and reading ahead on an interactive handle would
  swallow input the program has not asked for yet. PalSeek's own failure on a
  non-seekable fd is the test — no separate isatty is needed. }
procedure TFOpened(var f: Text);
begin
  TFResetBuf(f);
  f.Buffered := (f.Handle >= 0) and (PalSeek(f.Handle, 0, PAL_SEEK_CUR) >= 0);
end;

{ Make at least one byte available at f.Buf[f.BufPos]. False at end of file or
  on an I/O error, with the code in LastIOResult.

  `quiet` suppresses the success-path SetIO. TextReadLn needs that and is the
  only caller that does: it must not clear a stale I/O code that a {$I+}
  region's PXXIoCheck can still see. FAILURE always records, quiet or not. }
function TFFillEx(var f: Text; quiet: Boolean): Boolean;
var n: Int64; want: Integer;
begin
  if f.BufPos < f.BufLen then
  begin
    Result := True;
    Exit;
  end;
  if f.HitEof then
  begin
    if not quiet then SetIO(TF_OK);
    Result := False;
    Exit;
  end;
  if f.Handle < 0 then
  begin
    SetIO(TF_ERR_NOT_OPEN);
    f.HitEof := True;
    Result := False;
    Exit;
  end;
  TFResetBuf(f);
  if f.Buffered then want := TF_BUFSIZE else want := 1;
  n := PalRead(f.Handle, @f.Buf[0], want);
  if n > 0 then
  begin
    f.BufLen := Integer(n);
    if not quiet then SetIO(TF_OK);
    Result := True;
  end
  else
  begin
    if n < 0 then SetIO(Integer(n)) else SetIO(TF_OK);
    f.HitEof := True;
    Result := False;
  end;
end;

function TFFill(var f: Text): Boolean;
begin
  Result := TFFillEx(f, False);
end;

{ One byte from the cursor, False at end of file (or on an I/O error, with the
  code in LastIOResult). }
function TFNextByte(var f: Text; var c: Byte): Boolean;
begin
  if not TFFill(f) then
  begin
    Result := False;
    Exit;
  end;
  c := f.Buf[f.BufPos];
  Inc(f.BufPos);
  SetIO(TF_OK);
  Result := True;
end;

{ Un-read the byte TFNextByte just handed over. That byte is still in the
  buffer at BufPos-1, so stepping the cursor back IS the whole operation — there
  is nothing to store and nothing to keep in sync.

  `c` is therefore ignored in the normal case, and that is deliberate rather
  than sloppy: the parameter documents the contract (you may only push back what
  you just took) and keeps every call site readable. The else-branch below is
  the defensive path for a caller that broke it — park the byte rather than lose
  it, so a bug upstream costs a wrong cursor and not a vanished character. }
procedure TFPushBack(var f: Text; c: Byte);
begin
  if f.BufPos > 0 then
    Dec(f.BufPos)
  else
  begin
    f.Buf[0] := c;
    f.BufPos := 0;
    f.BufLen := 1;
  end;
end;

{ The delimiter set FPC's numeric reader uses: blank, tab, and both halves of a
  line ending. Line breaks count, which is why `readln(t, n, m)` over a file
  with one number per line still fills both. }
function TFIsSpace(c: Byte): Boolean;
begin
  Result := (c = 32) or (c = 9) or (c = 10) or (c = 13);
end;

procedure Assign(var f: Text; const path: AnsiString);
begin
  f.Handle := -1;
  f.Name := path;
  f.HitEof := False;
  f.Buffered := False;
  TFResetBuf(f);
  SetIO(TF_OK);
end;

procedure AssignFile(var f: Text; const path: AnsiString);
begin
  Assign(f, path);
end;

procedure Reset(var f: Text);
begin
  f.Handle := PalOpen(PChar(f.Name), PAL_OPEN_READ, 0);
  f.HitEof := False;
  TFOpened(f);
  if f.Handle < 0 then SetIO(f.Handle) else SetIO(TF_OK);
end;

procedure Rewrite(var f: Text);
begin
  f.Handle := PalOpen(PChar(f.Name),
    PAL_OPEN_WRITE or PAL_OPEN_CREATE or PAL_OPEN_TRUNC, 438);
  f.HitEof := False;
  TFOpened(f);
  if f.Handle < 0 then SetIO(f.Handle) else SetIO(TF_OK);
end;

procedure Append(var f: Text);
begin
  f.Handle := PalOpen(PChar(f.Name),
    PAL_OPEN_WRITE or PAL_OPEN_CREATE or PAL_OPEN_APPEND, 438);
  f.HitEof := False;
  TFOpened(f);
  if f.Handle < 0 then SetIO(f.Handle) else SetIO(TF_OK);
end;

procedure Close(var f: Text);
var rc, unread: Integer;
begin
  if f.Handle >= 0 then
  begin
    { THE trap of buffering, and the reason Buffered is gated on seekability:
      read-ahead leaves the descriptor past what the caller actually consumed.
      Anything that inherits or shares this fd — a child process, a dup — would
      then start from a position nobody asked for. Rewind by whatever is still
      sitting in the buffer before the handle goes away. }
    unread := f.BufLen - f.BufPos;
    if f.Buffered and (unread > 0) then
      PalSeek(f.Handle, -Int64(unread), PAL_SEEK_CUR);
    rc := PalClose(f.Handle);
    if rc < 0 then SetIO(rc) else SetIO(TF_OK);
  end
  else
    SetIO(TF_OK);
  f.Handle := -1;
  f.Buffered := False;
  TFResetBuf(f);
end;

procedure CloseFile(var f: Text);
begin
  Close(f);
end;

procedure Erase(var f: Text);
var rc: Integer;
begin
  { Classic Erase: delete the assigned (closed) file by name. }
  if f.Name = '' then
  begin
    SetIO(TF_ERR_NOT_ASSIGNED);
    Exit;
  end;
  rc := PalDelete(PChar(f.Name));
  if rc < 0 then SetIO(rc) else SetIO(TF_OK);
end;

function Eof(var f: Text): Boolean;
begin
  { "Is there a byte" is exactly "can the buffer produce one", and asking does
    not move the cursor — the byte stays where it is instead of being parked in
    a slot every other reader then has to remember to drain. }
  Result := not TFFill(f);
end;

function Eoln(var f: Text): Boolean;
begin
  if not TFFill(f) then
    Result := True
  else
    Result := (f.Buf[f.BufPos] = 10) or (f.Buf[f.BufPos] = 13);
end;

{ The bytes SeekEof and SeekEoln step over. MEASURED against FPC 3.2.2 rather
  than inferred — each of #1..#40 was written in front of an 'x' and the
  cursor's landing place read back:

    skipped:      #9 TAB, #26 SUB, #32 SPACE  (SeekEof also skips #10 and #13)
    NOT skipped:  #1..#8, #11, #12, #14..#25, #27..#31, #33 and up

  So the intuitive rule `c <= 32` is WRONG: it would swallow every other
  control byte. #26 is in the set because it is the DOS end-of-file marker and
  FPC steps over it exactly like blank space — a file holding only #26 is
  SeekEof-empty, while 'x'#26 still yields its 'x'.

  Deliberately NOT unified with TFIsSpace above. That one is the numeric
  tokeniser's DELIMITER set (blank, tab, and both halves of a line ending);
  this one is the seek routines' SKIP set. They overlap without being the same
  concept — #26 belongs only here, and #10/#13 delimit a token but must stop
  SeekEoln — so folding them together would make one of the two wrong. }
function TFIsSeekSpace(c: Byte): Boolean;
begin
  Result := (c = 9) or (c = 26) or (c = 32);
end;

function SeekEof(var f: Text): Boolean;
var c: Byte;
begin
  while TFNextByte(f, c) do
    if not (TFIsSeekSpace(c) or (c = 10) or (c = 13)) then
    begin
      TFPushBack(f, c);
      Result := False;
      Exit;
    end;
  { TFNextByte answers False at end of file AND on an I/O error, leaving the
    code in LastIOResult — the same conflation Eof makes, on purpose. }
  Result := True;
end;

function SeekEoln(var f: Text): Boolean;
var c: Byte;
begin
  while TFNextByte(f, c) do
    if not TFIsSeekSpace(c) then
    begin
      { The terminator is not ours to eat: push it back so Readln still sees a
        complete line. Measured — FPC leaves the cursor ON the #10 (or the #13
        of a CRLF) and answers True. }
      TFPushBack(f, c);
      Result := (c = 10) or (c = 13);
      Exit;
    end;
  Result := True;
end;

procedure Rename(var f: Text; const NewName: AnsiString);
var rc: Integer;
begin
  { An open handle is refused and the file left alone (FPC answers IOResult
    102 here; the code is ours, the refusal is FPC's). Same shape as Erase: a
    name-level operation on a closed, assigned handle. }
  if f.Handle >= 0 then
  begin
    SetIO(TF_ERR_NOT_ASSIGNED);
    Exit;
  end;
  if (f.Name = '') or (NewName = '') then
  begin
    SetIO(TF_ERR_NOT_ASSIGNED);
    Exit;
  end;
  rc := PalRename(PChar(f.Name), PChar(NewName));
  if rc < 0 then
  begin
    SetIO(rc);
    Exit;
  end;
  { The handle follows the file — measured: Reset(f) straight after a Rename
    opens the NEW name and reads its contents. }
  f.Name := NewName;
  SetIO(TF_OK);
end;

function IOResult: Integer;
begin
  Result := LastIOResult;
  LastIOResult := TF_OK;
end;

procedure TextWrite(var f: Text; const s: AnsiString);
var n: Int64;
begin
  if f.Handle < 0 then
  begin
    SetIO(TF_ERR_NOT_OPEN);
    Exit;
  end;
  n := PalWrite(f.Handle, PChar(s), Length(s));
  if n < 0 then SetIO(Integer(n)) else SetIO(TF_OK);
end;

procedure TextWriteLn(var f: Text; const s: AnsiString);
var nl: array[0..0] of Byte; n: Int64;
begin
  TextWrite(f, s);
  if LastIOResult <> TF_OK then Exit;
  nl[0] := 10;
  n := PalWrite(f.Handle, @nl[0], 1);
  if n < 0 then SetIO(Integer(n)) else SetIO(TF_OK);
end;

procedure TextReadLn(var f: Text; var s: AnsiString);
var n: Int64; c: Byte; done: Boolean;
begin
  s := '';
  done := False;
  while not done do
  begin
    { The quiet fill: on SUCCESS this must not touch LastIOResult, or a stale
      code a {$I+} region can still see would be cleared here. That is the whole
      reason this loop is not just TFNextByte. }
    if TFFillEx(f, True) then
    begin
      c := f.Buf[f.BufPos];
      Inc(f.BufPos);
      n := 1;
    end
    else
      n := 0;

    if n = 1 then
    begin
      if c = 10 then
        done := True
      else if c <> 13 then
        s := s + Chr(c);
    end
    else
    begin
      { TFFillEx has already recorded the reason (end of file, bad handle, or a
        read error) — do not overwrite it with TF_OK. }
      f.HitEof := True;
      done := True;
    end;
  end;
end;

procedure TextReadChar(var f: Text; var c: Char);
{ Reads through TFNextByte like every other reader, which is what makes them all
  agree about where the cursor is — the whole point, since a Char arm that read a
  LINE and took [1] would be right for the first read and silently wrong for
  every one after it. This procedure is exactly TFNextByte plus the
  end-of-file substitution. }
const
  TF_EOF_CHAR = 26;   { FPC yields ^Z at and past end of file, with no I/O error }
var b: Byte;
begin
  if TFNextByte(f, b) then
    c := Chr(b)
  else
    c := Chr(TF_EOF_CHAR);
end;

procedure TextReadNumTok(var f: Text; var s: AnsiString);
var c: Byte; done: Boolean;
begin
  s := '';
  { Whitespace first, line breaks included, to end of file. Running out here is
    FPC's `read(t, n)` on a file with nothing left in it: the token is empty,
    the caller's Val fails, and the destination stays 0 — which is what FPC
    yields for that case too. }
  done := False;
  while not done do
  begin
    if not TFNextByte(f, c) then Exit;
    done := not TFIsSpace(c);
  end;
  { Then to the next whitespace byte, which is put back rather than eaten. }
  done := False;
  while not done do
  begin
    s := s + Chr(c);
    if not TFNextByte(f, c) then
      done := True
    else if TFIsSpace(c) then
    begin
      TFPushBack(f, c);
      done := True;
    end;
  end;
end;

procedure TextReadStrTo(var f: Text; var s: AnsiString);
var c: Byte; done: Boolean;
begin
  s := '';
  done := False;
  while not done do
  begin
    if not TFNextByte(f, c) then
      done := True
    else if (c = 10) or (c = 13) then
    begin
      { Stop BEFORE the terminator and keep it — including a bare CR, which
        FPC's read(f, s) also stops at and leaves for readln to strip. }
      TFPushBack(f, c);
      done := True;
    end
    else
      s := s + Chr(c);
  end;
end;

procedure Flush(var f: Text);
begin
  { Writes are unbuffered (PAL writes hit the fd directly); nothing to drain. }
end;

initialization
  { Input and Output are deliberately NEVER buffered, even when stdin happens to
    be a redirected regular file and would pass the seekability test. Read-ahead
    on a shared descriptor is not ours to do: a program that reads a line and
    then execs a child sharing fd 0 would hand it a position it never asked for,
    and there is no Close on stdin at which to rewind. So the interactive path
    keeps exactly today's one-byte reads — this change buys file I/O, and buys
    it without touching the case where read-ahead is observable. }
  Input.Handle := 0;
  Input.Name := '';
  Input.HitEof := False;
  Input.Buffered := False;
  TFResetBuf(Input);
  Output.Handle := 1;
  Output.Name := '';
  Output.HitEof := False;
  Output.Buffered := False;
  TFResetBuf(Output);
end.
