program FileIO;
var
  buf: array[0..255] of Char;
  n, i: Integer;
  fname: string;

begin
  ArgStr(1, fname);
  writeln(fname);
  writeln(Length(fname));

  n := SysRead(SysOpen(fname, 0), buf, 255);
  writeln(n);

  for i := 0 to n-1 do
    writeln(buf[i]);
end.
