program lib_textfile;

uses textfile;

var
  f: Text;
  line: AnsiString;
  count: Integer;

begin
  Assign(f, '/tmp/pxx_lib_textfile.txt');
  Rewrite(f);
  TextWriteLn(f, 'alpha');
  TextWriteLn(f, 'beta');
  Close(f);

  AssignFile(f, '/tmp/pxx_lib_textfile.txt');
  Reset(f);
  count := 0;
  while not Eof(f) do
  begin
    TextReadLn(f, line);
    if line <> '' then
    begin
      writeln(line);
      count := count + 1;
    end;
  end;
  CloseFile(f);
  writeln('count=', count);
  writeln('io=', IOResult);
end.
