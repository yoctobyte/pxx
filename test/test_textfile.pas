{ Implicit text-file surface + file-handle keyword IO dispatch
  (feature-textfile-keyword-io-dispatch). No explicit `uses textfile` — a
  `var f: Text` declaration auto-loads lib/rtl/textfile.pas, and Write/WriteLn/
  ReadLn with a Text first arg dispatch to the PAL-backed RTL. The Text var is a
  PROC LOCAL (managed `Name: AnsiString` field must be zero-inited in the
  prologue — the up-front implicit load is what makes that happen). Built with
  -Fulib/rtl/platform/posix. }
program test_textfile;

procedure WriteData(const path: AnsiString);
var f: Text;
begin
  Assign(f, path);
  Rewrite(f);
  WriteLn(f, 'room=hall');
  Write(f, 'count=');
  WriteLn(f, 42);
  Close(f);
end;

procedure ReadData(const path: AnsiString);
var f: Text; s: AnsiString; i: Integer;
begin
  Assign(f, path);
  Reset(f);
  i := 0;
  while not Eof(f) do
  begin
    ReadLn(f, s);
    WriteLn('line', i, ': ', s);
    i := i + 1;
  end;
  Close(f);
end;

const PATH = '/tmp/test_textfile_data26.txt';
begin
  WriteData(PATH);
  ReadData(PATH);
  WriteLn('io=', IOResult);
end.
