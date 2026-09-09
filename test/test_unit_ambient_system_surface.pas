program test_unit_ambient_system_surface;
{ The unit calls sqrt/ln/exp/sin/cos/arctan/pi with no uses line; the PROGRAM
  names no math at all, so the program-level ambient scan cannot see them.
  Before the fix this was six `undefined variable` errors in the unit.
  bug-p-the-system-math-and-thread-surfaces-are-not-ambient-in-units

  Rows d..h are the SysUtils-side System names -- AllocMem, DynArraySize,
  SetString, sLineBreak, UTF8Decode/UTF8Encode -- and they are NOT the same
  class as rows a..c, which is a correction of what this header said when they
  were added.

  ROWS a..c HAVE A POSITIVE CONTROL AND ROWS d..h DO NOT. Measured 2026-09-09 at
  470240dd0eb5 by disabling each pull and rebuilding: with the unit-level MATH
  pull disabled this file is refused at `pi`, so rows a..c are asserting it.
  With a unit-level BUILTIN pull disabled the file compiles and every row still
  prints -- because any `uses` clause already pulls `builtin` (the tkUses arm)
  and a unit is only ever compiled because a program `uses` it, so `builtin` is
  in scope before any unit is parsed. `uses uambientsys` on line 14 is doing it.

  So rows d..h assert that the six names WORK and give fpc's values from inside
  a unit, which is worth having, and they cannot fail for a missing unit-level
  pull. Do not read a green here as covering one. Expected values are fpc
  3.2.2's for the identical source.
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
