program test_unit_ambient_system_surface;
{ The unit calls sqrt/ln/exp/sin/cos/arctan/pi with no uses line; the PROGRAM
  names no math at all, so the program-level ambient scan cannot see them.
  Before the fix this was six `undefined variable` errors in the unit.
  bug-p-the-system-math-and-thread-surfaces-are-not-ambient-in-units

  Rows d..h are the same class again for the SysUtils-side System names --
  AllocMem, DynArraySize, SetString, sLineBreak, UTF8Decode/UTF8Encode. THE
  PROGRAM NAMES NONE OF THEM, which is the point: if the ambient pull were only
  program-level (as it was for the math names before that fix) every one of
  them would be `undefined variable` inside the unit and this program would not
  compile. Expected values are fpc 3.2.2's for the identical source.
  task-b-nineteen-sysutils-names-that-fpc-keeps-in-system }
uses uambientsys;
begin
  writeln('a ', Hypot2(3.0, 4.0):0:4);
  writeln('b ', LogSum(1.0):0:4);
  writeln('c ', Circle(2.0):0:4);
  writeln('d ', SysAlloc);
  writeln('e ', SysDynLen);
  writeln('f ', SysSetStr);
  writeln('g ', SysLineBreakLen);
  writeln('h ', SysUtf8Round('abc'));
  writeln('OK');
end.
