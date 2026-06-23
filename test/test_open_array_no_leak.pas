{$mode objfpc}
program test_open_array_no_leak;

{ A fixed array passed to const/value AND var open-array params is copied into a
  frame/BSS-local [len][data] buffer (not a per-call heap dyn temp), so a hot
  loop must not leak. 2M total calls: pre-fix leaked ~94 MB (the Makefile runs
  this under a vsize cap so a regression OOMs); post-fix RSS ~264 KB. Output:
  "ok 1000000". }

procedure C(const a: array of AnsiString);
var i, s: Integer;
begin
  s := 0;
  for i := 0 to High(a) do s := s + Length(a[i]);
end;

procedure V(var a: array of Integer);
var i: Integer;
begin
  for i := 0 to High(a) do a[i] := a[i] + 1;
end;

var
  sa: array[0..2] of AnsiString;
  ia: array[0..2] of Integer;
  k: Integer;
begin
  sa[0] := 'aa'; sa[1] := 'bb'; sa[2] := 'cc';
  ia[0] := 0; ia[1] := 0; ia[2] := 0;
  for k := 1 to 1000000 do
  begin
    C(sa);
    V(ia);
  end;
  writeln('ok ', ia[0]);
end.
