program rq;
uses sysutils;
var b: byte; i: integer; a: array[1..3] of integer; caught: Integer;
begin
  caught := 0;
  {$R+}
  i := 256;
  try b := i; writeln('b ', b); except on erangeerror do inc(caught); end;
  i := 4;
  try a[i] := 1; writeln('a ok'); except on erangeerror do inc(caught); end;
  i := -1;
  try b := i; writeln('b2 ', b); except on erangeerror do inc(caught); end;
  {$R-}
  i := 300; b := i;
  writeln('lax-b ', b);
  writeln('caught=', caught);
end.
