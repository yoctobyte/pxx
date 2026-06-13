program test_cross_sysopen_family;

{ Public SysOpen/SysRead/SysWrite/SysClose/SysFchmod oracle. The temp file is
  created with SysOpen's fixed mode=0 path, then made readable via SysFchmod
  before reopening. Compile with -dPXX_MANAGED_STRING for cross managed paths. }

var
  path: AnsiString;
  outbuf: array[0..7] of Char;
  inbuf: array[0..7] of Char;
  fd, n, i: Integer;

begin
  path := '/tmp/frankonpiler_sysopen_family.tmp';
  outbuf[0] := 'P';
  outbuf[1] := 'X';
  outbuf[2] := 'X';
  outbuf[3] := '2';
  outbuf[4] := '6';

  fd := SysOpen(path, 577); { O_WRONLY | O_CREAT | O_TRUNC }
  n := SysWrite(fd, outbuf, 5);
  writeln(n);
  SysFchmod(fd, 420);      { 0644 decimal }
  SysClose(fd);

  fd := SysOpen(path, 0);
  n := SysRead(fd, inbuf, 5);
  writeln(n);
  SysClose(fd);

  for i := 0 to n - 1 do
    writeln(inbuf[i]);
end.
