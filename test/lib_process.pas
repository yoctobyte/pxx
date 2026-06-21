program lib_process;

uses sysutils, platform;

var
  pid: Integer;
  childStdin, childStdout: Integer;
  args: array of AnsiString;
  buf: array of Byte;
  n: Int64;
  wstatus: Integer;
  i: Integer;
  s: AnsiString;
begin
  childStdin := -1;
  childStdout := -1;
  
  SetLength(args, 2);
  args[0] := 'hello';
  args[1] := 'world';

  SetLength(buf, 64);

  pid := ExecutePipeline('/bin/echo', args, childStdin, childStdout);
  if pid <= 0 then
  begin
    writeln('ExecutePipeline failed');
    halt(1);
  end;

  { Read from stdout }
  for i := 0 to 63 do buf[i] := 0;
  n := PalRead(childStdout, @buf[0], 64);
  writeln('Bytes read: ', Integer(n));
  if n > 0 then
  begin
    s := '';
    for i := 0 to Integer(n) - 1 do
    begin
      s := s + Chr(buf[i]);
      writeln('Byte ', i, ': ', buf[i]);
    end;
    writeln('Child output: [', s, ']');
  end;

  { Wait for child }
  wstatus := 0;
  PalWait4(pid, @wstatus, 0, nil);
  writeln('Child wait status: ', wstatus);
  
  PalClose(childStdout);
  writeln('OK');
end.
