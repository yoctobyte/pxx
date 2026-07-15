program test_range_checks_enum_field;
{ {$R+} slice 3: chr(out-of-range) into a Char dest and a record-FIELD static
  array index both raise catchable ERangeError (FPC-parity); an explicit enum
  CAST is NOT checked (FPC doesn't either — oracle-verified). Named-subrange dests check their retained lo..hi.
  feature-pascal-range-checks-r-plus. }
uses sysutils;
type TE = (e0, e1, e2); TSub = 3..7;
     TR = record arr: array[1..3] of integer; fs: TSub; end;
var e: TE; sb: TSub; ch: char; i: integer; r: TR; caught: Integer;
begin
  caught := 0;
  {$R+}
  i := 9;
  try e := TE(i); writeln('e ', Ord(e)); except on erangeerror do inc(caught); end;
  i := 300;
  try ch := chr(i); writeln('ch ', Ord(ch)); except on erangeerror do inc(caught); end;
  i := 99;
  try sb := i; writeln('sb ', sb); except on erangeerror do inc(caught); end;
  sb := 5;
  try r.fs := i; writeln('fs ', r.fs); except on erangeerror do inc(caught); end;
  r.fs := 4;
  i := 5;
  try r.arr[i] := 1; writeln('fld ok'); except on erangeerror do inc(caught); end;
  i := 2;
  r.arr[i] := 7;
  writeln('ok ', r.arr[2], ' ', sb, ' ', r.fs, ' caught=', caught);
end.
