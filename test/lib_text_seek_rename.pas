{ SeekEof / SeekEoln / Rename — the whitespace-tolerant loop conditions and the
  Text-handle rename (feature-b-text-file-surface-seekeof-rename-settextbuf).

  Every expectation here was MEASURED against FPC 3.2.2, not inferred. The skip
  set in particular is not what it looks like: an oracle wrote each of #1..#40
  in front of an 'x' and read back where the cursor landed, and only THREE
  bytes are stepped over —

      #9 TAB, #26 SUB, #32 SPACE      (SeekEof also steps over #10 and #13)

  — while #1..#8, #11, #12, #14..#25, #27..#31 and #33 up all stop the scan. So
  the obvious rule `c <= 32` is wrong, and the rows below pin the boundary at
  #1, #31 and #33 precisely so a future "simplification" to `c <= 32` fails
  here instead of silently eating control bytes out of a data file.

  #26 is in the set because it is the DOS end-of-file marker: FPC steps over it
  like blank space, so a file holding only #26 is SeekEof-empty while 'x'#26
  still yields its 'x'. Both of those are measured rows below.

  The other subject is the CURSOR. Both routines consume the whitespace they
  skip and neither consumes the byte that stops them, so every row records what
  the next read returns as well as what the seek answered — a test that only
  checked the Boolean would pass an implementation that ate the token. }
program lib_text_seek_rename;

uses textfile, sysutils;

var
  failures: Integer;
  dir: AnsiString;

procedure Fail(const what, got, want: AnsiString);
begin
  Inc(failures);
  WriteLn('FAIL ', what, ': got ', got, ' want ', want);
end;

procedure CheckI(const what: AnsiString; got, want: Integer);
begin
  if got <> want then Fail(what, IntToStr(got), IntToStr(want));
end;

procedure CheckB(const what: AnsiString; got, want: Boolean);
var g, w: AnsiString;
begin
  if got = want then Exit;
  if got then g := 'True' else g := 'False';
  if want then w := 'True' else w := 'False';
  Fail(what, g, w);
end;

function DataPath(const stem: AnsiString): AnsiString;
begin
  Result := dir + stem;
end;

procedure Put(const path, content: AnsiString);
var g: Text;
begin
  Assign(g, path);
  Rewrite(g);
  TextWrite(g, content);
  Close(g);
end;

{ -1 means "at end of file"; otherwise the ordinal of the next byte. Reported
  alongside every seek result because the cursor is half the contract. }
function NextOrd(var f: Text): Integer;
var c: Char;
begin
  if Eof(f) then
  begin
    Result := -1;
    Exit;
  end;
  TextReadChar(f, c);
  Result := Ord(c);
end;

procedure TEof(const tag, content: AnsiString; wantSeek: Boolean; wantNext: Integer);
var f: Text; path: AnsiString;
begin
  path := DataPath('seek.dat');
  Put(path, content);
  Assign(f, path);
  Reset(f);
  CheckB('SeekEof ' + tag, SeekEof(f), wantSeek);
  CheckI('SeekEof-cursor ' + tag, NextOrd(f), wantNext);
  Close(f);
end;

procedure TEoln(const tag, content: AnsiString; wantSeek: Boolean; wantNext: Integer);
var f: Text; path: AnsiString;
begin
  path := DataPath('seek.dat');
  Put(path, content);
  Assign(f, path);
  Reset(f);
  CheckB('SeekEoln ' + tag, SeekEoln(f), wantSeek);
  CheckI('SeekEoln-cursor ' + tag, NextOrd(f), wantNext);
  Close(f);
end;

{ The reason the pair exists: a table with a trailing newline. Written with Eof
  this loop reads one junk value past the end; written with SeekEof it does not.
  Both halves are asserted so the test states the motivation, not just the API. }
procedure TSumLoop;
var f: Text; path, tok: AnsiString; sum, n, guard: Integer;
begin
  path := DataPath('sum.dat');
  Put(path, ' 10 20'#10'30 '#10);
  Assign(f, path);
  Reset(f);
  sum := 0;
  guard := 0;
  while (not SeekEof(f)) and (guard < 100) do
  begin
    TextReadNumTok(f, tok);
    sum := sum + StrToIntDef(tok, 0);
    Inc(guard);
  end;
  Close(f);
  CheckI('SeekEof sum loop', sum, 60);
  CheckI('SeekEof sum loop iterations', guard, 3);

  { Same file, Eof as the condition: the fourth pass sees only the trailing
    newline, so the token is empty and the loop does an extra turn. That is the
    bug SeekEof exists to remove, asserted rather than described. }
  Assign(f, path);
  Reset(f);
  n := 0;
  guard := 0;
  while (not Eof(f)) and (guard < 100) do
  begin
    TextReadNumTok(f, tok);
    Inc(guard);
    if tok = '' then Inc(n);
  end;
  Close(f);
  CheckI('Eof loop takes an extra empty turn', n, 1);
end;

{ Everything from here to the end of TRename deliberately provokes I/O errors
  — wiping a file that may be absent, renaming an open handle, opening a name
  that must NOT exist — so the checks are explicit IOResult reads and the
  region turns the automatic {$I+} check off. Each case asserts the code. }
{$I-}

{ Delete by name if present, so a rerun in a dirty TESTTMP starts clean. }
procedure Wipe(const path: AnsiString);
var g: Text;
begin
  Assign(g, path);
  Erase(g);
  if IOResult = 0 then ;   { absent is fine — drain the code either way }
end;

procedure TRename;
var f: Text; oldp, newp, s: AnsiString;
begin
  oldp := DataPath('ren_old.dat');
  newp := DataPath('ren_new.dat');
  Wipe(oldp);
  Wipe(newp);
  Wipe(DataPath('ren_open.dat'));
  Wipe(DataPath('ren_x.dat'));
  Put(oldp, 'payload'#10);

  Assign(f, oldp);
  Rename(f, newp);
  CheckI('Rename closed handle io', IOResult, 0);

  { The handle follows the file: Reset opens the NEW name. Measured on FPC. }
  Reset(f);
  CheckI('Rename then Reset io', IOResult, 0);
  TextReadLn(f, s);
  if s <> 'payload' then Fail('Rename then read back', s, 'payload');
  Close(f);

  { An OPEN handle is refused and the file is left alone (FPC answers 102 and
    does not rename; the code is ours, the refusal is FPC's). }
  Assign(f, newp);
  Reset(f);
  Rename(f, DataPath('ren_open.dat'));
  if IOResult = 0 then Fail('Rename open handle', 'accepted', 'refused');
  Close(f);
  Assign(f, DataPath('ren_open.dat'));
  Reset(f);
  if IOResult = 0 then
  begin
    Fail('Rename open handle left a file behind', 'ren_open.dat exists', 'absent');
    Close(f);
  end;

  { A name that is not there fails and reports it. }
  Assign(f, DataPath('ren_missing.dat'));
  Rename(f, DataPath('ren_x.dat'));
  if IOResult = 0 then Fail('Rename missing file', 'accepted', 'refused');
end;

{$I+}

begin
  failures := 0;
  dir := GetEnvironmentVariable('TESTTMP');
  if dir = '' then dir := GetTempDir;
  if (Length(dir) > 0) and (dir[Length(dir)] <> '/') then dir := dir + '/';

  { SeekEof: skips TAB, SUB, SPACE, LF and CR; stops on anything else. }
  TEof('spaces',        '  x',            False, 120);
  TEof('tabs',          #9#9'x',          False, 120);
  TEof('lf',            #10'x',           False, 120);
  TEof('crlf',          #13#10'x',        False, 120);
  TEof('blank only',    '   ',            True,  -1);
  TEof('blank then lf', '  '#10,          True,  -1);
  TEof('empty',         '',               True,  -1);
  TEof('sub then x',    #26'x',           False, 120);
  TEof('sub only',      #26,              True,  -1);
  TEof('x then sub',    'x'#26,           False, 120);
  TEof('bare x',        'x',              False, 120);
  TEof('blank lf blank','  '#10'  x',     False, 120);
  { The boundary. #1, #31 and #33 are NOT whitespace, however much `c <= 32`
    would like two of them to be. }
  TEof('ctrl 1',        #1'x',            False, 1);
  TEof('ctrl 31',       #31'x',           False, 31);
  TEof('punct 33',      #33'x',           False, 33);

  { SeekEoln: same set MINUS the line terminators, which stop it instead. }
  TEoln('spaces',        '  x',           False, 120);
  TEoln('tabs',          #9#9'x',         False, 120);
  TEoln('lf',            #10'x',          True,  10);
  TEoln('crlf',          #13#10'x',       True,  13);
  TEoln('blank only',    '   ',           True,  -1);
  TEoln('blank then lf', '  '#10,         True,  10);
  TEoln('empty',         '',              True,  -1);
  TEoln('sub then x',    #26'x',          False, 120);
  TEoln('sub then lf',   #26#10,          True,  10);
  TEoln('blank sub blank',' '#26' ',      True,  -1);
  TEoln('bare x',        'x',             False, 120);
  TEoln('ctrl 1',        #1'x',           False, 1);

  TSumLoop;
  TRename;

  if failures = 0 then
    WriteLn('TEXTSEEK OK')
  else
    WriteLn('TEXTSEEK FAILED ', failures);
end.
