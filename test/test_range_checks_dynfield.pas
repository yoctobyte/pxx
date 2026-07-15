program rdf;
uses sysutils;
type TR = record d: array of integer; end;
var r: TR; i: integer; caught: Integer;
begin
  caught := 0;
  SetLength(r.d, 3);
  {$R+}
  i := 7;
  try i := r.d[i]; writeln('rd ', i); except on erangeerror do inc(caught); end;
  try r.d[i] := 1; writeln('wr ok'); except on erangeerror do inc(caught); end;
  writeln('caught=', caught);
end.
