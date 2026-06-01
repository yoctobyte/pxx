program test_c_float;
{ Exercises the SysV float C-call ABI: double args in xmm, int args in
  integer registers (independent classing), and float return via xmm0. }
function pow(b, e: Double): Double; cdecl; external 'libm.so.6';
function sqrt(x: Double): Double; cdecl; external 'libm.so.6';
function ldexp(x: Double; e: Integer): Double; cdecl; external 'libm.so.6';
begin
  writeln(pow(2.0, 10.0):0:1);
  writeln(sqrt(256.0):0:1);
  writeln(ldexp(1.5, 3):0:1);
end.
