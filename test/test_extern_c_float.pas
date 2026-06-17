program test_extern_c_float;
{ External C calls (cross): float/double + Int64/UInt64 ABI breadth.
  Exercises double args/returns (atof/pow), single arg/return (sqrtf), and
  64-bit args/returns (atoll/llabs) across libc + libm. The same program
  links the native libraries on x86-64, so its output is the reference. }

function atof(s: PChar): double; cdecl; external 'libc.so.6';
function atoll(s: PChar): Int64; cdecl; external 'libc.so.6';
function llabs(x: Int64): Int64; cdecl; external 'libc.so.6';
function pow(b, e: double): double; cdecl; external 'libm.so.6';
function sqrtf(x: single): single; cdecl; external 'libm.so.6';

var
  d: double;
  q: Int64;
  f: single;
begin
  d := atof(PChar('2.5'));
  writeln(d);
  d := pow(2.0, 10.0);
  writeln(d);
  d := pow(d, 0.5);          { sqrt(1024) = 32 }
  writeln(d);
  q := atoll(PChar('9000000000'));
  writeln(q);
  q := llabs(-1234567890123);
  writeln(q);
  f := 6.25;
  f := sqrtf(f);             { 2.5 }
  writeln(f);
end.
