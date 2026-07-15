program rr;
uses sysutils;
var a: array[1..3] of integer; d: array of integer; i, v: integer; caught: Integer;
begin
  caught := 0;
  a[1] := 10; a[2] := 20; a[3] := 30;
  {$R+}
  i := 4;
  try v := a[i]; writeln('read ', v); except on erangeerror do inc(caught); end;
  i := 0;
  try v := a[i]; writeln('read0 ', v); except on erangeerror do inc(caught); end;
  SetLength(d, 3);
  i := 5;
  try v := d[i]; writeln('dyn ', v); except on erangeerror do inc(caught); end;
  try d[i] := 9; writeln('dynw ok'); except on erangeerror do inc(caught); end;
  writeln('caught=', caught);
end.
