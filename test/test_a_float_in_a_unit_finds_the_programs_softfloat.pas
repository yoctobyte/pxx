program test_a_float_in_a_unit_finds_the_programs_softfloat;
{ The program names softfloat; the unit it uses does not. On bare ESP this
  failed INSIDE the unit with "add `uses softfloat` to the program" while the
  program already had it. Build-only, like the other bare rows.
  bug-a-the-no-fpu-diagnostic-advises-uses-softfloat-which-does-not-help }
uses softfloat, usfalias;
var x: TF; i: Integer;
begin
  x := Half(7);
  i := Trunc(x);
  if i = 3 then Halt(0) else Halt(1);
end.
