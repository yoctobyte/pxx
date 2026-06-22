{$mode objfpc}
program test_var_open_array;

{ A static array passed to a `var`/`out` open-array parameter
  (bug-var-open-array-fixed-arg-length). The bare static-array address has no
  length header, so High/Length over the param used to return garbage (-1) and
  writes did not propagate. The fix copies the static array into a header'd dyn
  temp (copy-in) and copies the temp back after the call (copy-out), so:
    - High(a) / indexing over the param read correct values, and
    - the callee's writes land back in the caller's array.
  FPC oracle: 6 then "0 10 20 30 ". }

function SumA(var a: array of Integer): Integer;
var i: Integer;
begin
  Result := 0;
  for i := 0 to High(a) do Result := Result + a[i];
end;

procedure Fill(var a: array of Integer; n: Integer);
var i: Integer;
begin
  for i := 0 to High(a) do a[i] := n * i;
end;

var
  f: array[0..3] of Integer;
  i: Integer;
begin
  f[0] := 1; f[1] := 2; f[2] := 3; f[3] := 0;
  WriteLn(SumA(f));                       { 6  (read through var open array) }
  Fill(f, 10);                            { writes propagate back }
  for i := 0 to 3 do Write(f[i], ' ');
  WriteLn;                                { 0 10 20 30 }
end.
