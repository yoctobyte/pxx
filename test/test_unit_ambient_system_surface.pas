program test_unit_ambient_system_surface;
{ The unit calls sqrt/ln/exp/sin/cos/arctan/pi with no uses line; the PROGRAM
  names no math at all, so the program-level ambient scan cannot see them.
  Before the fix this was six `undefined variable` errors in the unit.
  bug-p-the-system-math-and-thread-surfaces-are-not-ambient-in-units }
uses uambientsys;
begin
  writeln('a ', Hypot2(3.0, 4.0):0:4);
  writeln('b ', LogSum(1.0):0:4);
  writeln('c ', Circle(2.0):0:4);
  writeln('OK');
end.
