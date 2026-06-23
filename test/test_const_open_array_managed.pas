{$mode objfpc}
program test_const_open_array_managed;

{ A `const` open-array of a MANAGED element (AnsiString) given a fixed-array
  argument: High/indexing must work and the caller's strings must survive (no
  over-release). Sibling of the var/out fix; the value/const path excluded managed
  elements (bug-const-open-array-managed-elem-length, High was -1). Also covers a
  trailing scalar parameter (variable) after the open array (the cross-unit crash
  case). FPC oracle: high=2 sel=1 /  aa / >bb /  cc / aabbcc. }

procedure P(const a: array of AnsiString; sel: Integer);
var i: Integer;
begin
  writeln('high=', High(a), ' sel=', sel);
  for i := 0 to High(a) do
    if i = sel then writeln('>', a[i]) else writeln(' ', a[i]);
end;

var
  arr: array[0..2] of AnsiString;
  v: Integer;
begin
  arr[0] := 'aa'; arr[1] := 'bb'; arr[2] := 'cc';
  v := 1;
  P(arr, v);                          { trailing scalar = variable }
  writeln(arr[0] + arr[1] + arr[2]);  { use after the call -> aabbcc (not freed) }
end.
