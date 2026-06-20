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
function Eof(var f: Text): Boolean;
function IOResult: Integer;

procedure TextWrite(var f: Text; const s: AnsiString);
procedure TextWriteLn(var f: Text; const s: AnsiString);
procedure TextReadLn(var f: Text; var s: AnsiString);

implementation

const
  TF_OK = 0;

var
  LastIOResult: Integer;

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

end.
