{ %FAIL-style negative: the non-string half of the same hole.

  `i.Bogus` on an Integer COMPILED and evaluated to i itself; a Double answered
  0, a Boolean 1. Separate from test_scalar_member_fail.pas because the two take
  different arms of the diagnostic — the string arm names the missing Delphi
  helpers, this one states the general rule — and a single test would pin only
  whichever arm it happened to hit.
  bug-p-a-member-on-a-scalar-silently-reads-the-values-own-bytes }
program test_scalar_member_int_fail;
var i: Integer;
begin
  i := 7;
  writeln(i.Bogus);
end.
