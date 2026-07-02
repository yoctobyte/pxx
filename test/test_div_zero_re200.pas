program test_div_zero_re200;
{ Integer div/mod by zero = clean FPC-style "Runtime error 200" + exit code 200
  instead of a raw uncatchable SIGFPE core dump
  (bug-integer-div-zero-sigfpe-uncatchable, x86-64 slice; opt-out via
  --no-div-check). Run with arg 'mod' for the mod path, no arg for div. The
  AnsiString var forces builtinheap in, exercising the PXXDivZero helper path
  (heap-free programs take the emitted Div0Stub instead — same message). }
var
  i, z: Int64;
  s: AnsiString;
begin
  { sanity: non-zero divisors unaffected by the check }
  writeln(100 div 7, ' ', 100 mod 7, ' ', (-100) div 7);
  s := 'before';
  writeln(s);
  z := 0; i := 7;
  if ParamStr(1) = 'mod' then
    i := i mod z
  else
    i := i div z;
  writeln('unreachable ', i);
end.
