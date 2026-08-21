program test_aintostr_negative;
{ The carrier for the AIntToStr negative-number test — see
  test/aintostr_units/builtinheap.pas for what is actually being tested and why
  it needs a prop.

  All this program has to do is make the compiler pull builtinheap ambiently,
  which a managed string does. It is never expected to run under the test rows
  that use -Fu; the Makefile also compiles it WITHOUT -Fu as the positive
  control, and then it must build and print `ok` like any other program —
  proving the impostor unit is doing the work and the failure is not something
  about this program.

  bug-a-aintostr-returns-empty-for-negative-numbers }
var s: AnsiString;
begin
  s := 'ok';
  writeln(s);
end.
