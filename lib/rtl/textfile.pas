{ SPDX-License-Identifier: Zlib }
unit textfile;
{ Classic text-file primitives on top of PAL byte handles.

  The compiler still treats ReadLn/WriteLn as keywords, so file-handle keyword
  forms need a small compiler hook. This unit provides the underlying RTL
  surface with explicit TextReadLn/TextWriteLn entry points. }

interface

uses platform;

type
  Text = record
    Handle: Integer;
    Name: AnsiString;
    HitEof: Boolean;
    HasPeek: Boolean;
    Peek: Byte;
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

procedure SetIO(code: Integer);
begin
  LastIOResult := code;
end;

procedure Assign(var f: Text; const path: AnsiString);
begin
  f.Handle := -1;
  f.Name := path;
  f.HitEof := False;
  f.HasPeek := False;
  f.Peek := 0;
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
  f.HasPeek := False;
  if f.Handle < 0 then SetIO(f.Handle) else SetIO(TF_OK);
end;

procedure Rewrite(var f: Text);
begin
  f.Handle := PalOpen(PChar(f.Name),
    PAL_OPEN_WRITE or PAL_OPEN_CREATE or PAL_OPEN_TRUNC, 438);
  f.HitEof := False;
  f.HasPeek := False;
  if f.Handle < 0 then SetIO(f.Handle) else SetIO(TF_OK);
end;

procedure Append(var f: Text);
begin
  f.Handle := PalOpen(PChar(f.Name),
    PAL_OPEN_WRITE or PAL_OPEN_CREATE or PAL_OPEN_APPEND, 438);
  f.HitEof := False;
  f.HasPeek := False;
  if f.Handle < 0 then SetIO(f.Handle) else SetIO(TF_OK);
end;

procedure Close(var f: Text);
var rc: Integer;
begin
  if f.Handle >= 0 then
  begin
    rc := PalClose(f.Handle);
    if rc < 0 then SetIO(rc) else SetIO(TF_OK);
  end
  else
    SetIO(TF_OK);
  f.Handle := -1;
  f.HasPeek := False;
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
    SetIO(-1);
    Exit;
  end;
  rc := PalDelete(PChar(f.Name));
  if rc < 0 then SetIO(rc) else SetIO(TF_OK);
end;

function Eof(var f: Text): Boolean;
var one: array[0..0] of Byte; n: Int64;
begin
  if f.HitEof then
  begin
    Result := True;
    Exit;
  end;
  if f.HasPeek then
  begin
    Result := False;
    Exit;
  end;
  if f.Handle < 0 then
  begin
    SetIO(-1);
    f.HitEof := True;
    Result := True;
    Exit;
  end;
  n := PalRead(f.Handle, @one[0], 1);
  if n = 1 then
  begin
    f.Peek := one[0];
    f.HasPeek := True;
    SetIO(TF_OK);
    Result := False;
  end
  else
  begin
    if n < 0 then SetIO(Integer(n)) else SetIO(TF_OK);
    f.HitEof := True;
    Result := True;
  end;
end;

function Eoln(var f: Text): Boolean;
begin
  { Eof does the lookahead and parks the byte in f.Peek, so asking it first
    both answers the end-of-file case and guarantees Peek is loaded. }
  if Eof(f) then
    Result := True
  else
    Result := (f.Peek = 10) or (f.Peek = 13);
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
    SetIO(-1);
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
var one: array[0..0] of Byte; n: Int64; c: Byte; done: Boolean;
begin
  s := '';
  done := False;
  while not done do
  begin
    if f.HasPeek then
    begin
      c := f.Peek;
      f.HasPeek := False;
      n := 1;
    end
    else
    begin
      if f.Handle < 0 then
      begin
        SetIO(-1);
        f.HitEof := True;
        Exit;
      end;
      n := PalRead(f.Handle, @one[0], 1);
      c := one[0];
    end;

    if n = 1 then
    begin
      if c = 10 then
        done := True
      else if c <> 13 then
        s := s + Chr(c);
    end
    else
    begin
      if n < 0 then SetIO(Integer(n)) else SetIO(TF_OK);
      f.HitEof := True;
      done := True;
    end;
  end;
  if LastIOResult = TF_OK then SetIO(TF_OK);
end;

procedure TextReadChar(var f: Text; var c: Char);
{ The pushback this needs already exists: Eof reads one byte ahead and parks it
  in f.Peek, and TextReadLn drains it before touching the fd. Consuming from the
  same slot is what makes the two agree about where the cursor is — which is the
  whole point, since a Char arm that read a LINE and took [1] would be right for
  the first read and silently wrong for every one after it. }
const
  TF_EOF_CHAR = 26;   { FPC yields ^Z at and past end of file, with no I/O error }
var one: array[0..0] of Byte; n: Int64;
begin
  if f.HasPeek then
  begin
    c := Chr(f.Peek);
    f.HasPeek := False;
    SetIO(TF_OK);
    Exit;
  end;
  if f.HitEof then
  begin
    c := Chr(TF_EOF_CHAR);
    SetIO(TF_OK);
    Exit;
  end;
  if f.Handle < 0 then
  begin
    SetIO(-1);
    f.HitEof := True;
    c := Chr(TF_EOF_CHAR);
    Exit;
  end;
  n := PalRead(f.Handle, @one[0], 1);
  if n = 1 then
  begin
    c := Chr(one[0]);
    SetIO(TF_OK);
  end
  else
  begin
    if n < 0 then SetIO(Integer(n)) else SetIO(TF_OK);
    f.HitEof := True;
    c := Chr(TF_EOF_CHAR);
  end;
end;

procedure Flush(var f: Text);
begin
  { Writes are unbuffered (PAL writes hit the fd directly); nothing to drain. }
end;

initialization
  Input.Handle := 0;
  Input.Name := '';
  Input.HitEof := False;
  Input.HasPeek := False;
  Output.Handle := 1;
  Output.Name := '';
  Output.HitEof := False;
  Output.HasPeek := False;
end.
