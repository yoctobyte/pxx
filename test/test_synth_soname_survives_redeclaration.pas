{ A LIBRARY RESOLVED FOR AN EXTERNAL MUST SURVIVE EVERY LATER DECLARATION OF
  THE SAME NAME -- see test/chdrsynth/m/synthclob.h for the three writes and
  why each is needed.

  This binary RUNS, which is the assertion that matters: before the fix it
  built with no diagnostic and died at exec with
  `libsynthclob.so: cannot open shared object file`. The readelf rows beside it
  say the same thing one layer down, and are there so a failure names the cause
  instead of an exit code.
  bug-c-an-unresolvable-synthesised-soname-still-reaches-dt-needed }
program test_synth_soname_survives_redeclaration;
uses synthclob;
var a, b: array[0..3] of Byte;
    i: Integer;
begin
  for i := 0 to 3 do begin a[i] := i; b[i] := i; end;
  WriteLn(sc_cmp(@a[0], @b[0], 4));
end.
