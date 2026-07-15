program test_param_array_lowbound;
{ A named fixed-array PARAM (var a: TA where TA = array[1..3]) kept lo=0
  internally, so a[1] := x silently wrote the NEXT element (0 7 instead of
  7 8) — found by the {$R+} arc's oracle probe. Also pins the {$R+}
  open-array-param and fixed-param index checks.
  bug found under feature-pascal-range-checks-r-plus. }
uses sysutils;
type TA = array[1..3] of integer;
var caught: Integer;
procedure P(var a: TA);
var i: integer;
begin
  {$R+}
  a[1] := 7;
  a[2] := 8;
  i := 9;
  try a[i] := 1; writeln('w ok'); except on erangeerror do inc(caught); end;
end;
procedure Q(a: array of integer);
var i: integer;
begin
  {$R+}
  i := 5;
  try i := a[i]; writeln('rd ', i); except on erangeerror do inc(caught); end;
end;
var g: TA;
begin
  caught := 0;
  g[1] := 0; g[2] := 0; g[3] := 0;
  P(g);
  Q(g);
  writeln(g[1], ' ', g[2], ' caught=', caught);
end.
