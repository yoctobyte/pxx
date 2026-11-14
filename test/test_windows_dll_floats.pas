program test_windows_dll_floats;
{ Floating-point arguments to a C library: libc on Linux, msvcrt.dll under
  --os=windows, where the call site has to move every argument from its SysV
  register (integers and floats counted apart) to its Microsoft x64 slot
  (position decides: rcx/xmm0, rdx/xmm1, r8/xmm2, r9/xmm3, then the stack).
  The rows cover a float first, floats after integers, a float on the stack
  (argument 5+), a single, and a variadic call, where Microsoft also wants
  each float in its integer register. Same output on both. (On Linux the
  math functions live in libm.)
  feature-port-windows-pe }

{$ifdef PXX_OS_WINDOWS}
function c_pow(x, y: Double): Double; cdecl; external 'msvcrt.dll' name 'pow';
function c_ldexp(x: Double; e: LongInt): Double; cdecl; external 'msvcrt.dll' name 'ldexp';
function c_gcvt(v: Double; digits: LongInt; buf: PChar): PChar; cdecl; external 'msvcrt.dll' name '_gcvt';
function c_atan2(y, x: Double): Double; cdecl; external 'msvcrt.dll' name 'atan2';
function c_powf(x, y: Single): Single; cdecl; external 'msvcrt.dll' name 'powf';
function c_sprintf(buf, fmt: PChar): LongInt; cdecl; varargs; external 'msvcrt.dll' name 'sprintf';
{$else}
function c_pow(x, y: Double): Double; cdecl; external 'libm.so.6' name 'pow';
function c_ldexp(x: Double; e: LongInt): Double; cdecl; external 'libm.so.6' name 'ldexp';
function c_gcvt(v: Double; digits: LongInt; buf: PChar): PChar; cdecl; external 'libc.so.6' name 'gcvt';
function c_atan2(y, x: Double): Double; cdecl; external 'libm.so.6' name 'atan2';
function c_powf(x, y: Single): Single; cdecl; external 'libm.so.6' name 'powf';
function c_sprintf(buf, fmt: PChar): LongInt; cdecl; varargs; external 'libc.so.6' name 'sprintf';
{$endif}

var
  buf: array[0..255] of Char;
  n: LongInt;
begin
  writeln('pow ', c_pow(2.0, 10.0):0:1);
  writeln('ldexp ', c_ldexp(1.5, 4):0:1);
  c_gcvt(3.25, 6, @buf[0]);
  writeln('gcvt ', PChar(@buf[0]));
  writeln('atan2 ', c_atan2(1.0, 1.0) * 4:0:6);
  writeln('powf ', c_powf(1.5, 2.0):0:4);
  n := c_sprintf(@buf[0], '%d %.2f %d %.3f %s %.1f', 7, 2.5, -3, 0.125, PChar('mid'), 9.75);
  writeln('sprintf ', n, ' [', PChar(@buf[0]), ']');
  n := c_sprintf(@buf[0], '%.1f %.1f %.1f %.1f %.1f %d', 1.0, 2.0, 3.0, 4.0, 5.0, 42);
  writeln('sprintf ', n, ' [', PChar(@buf[0]), ']');
end.
