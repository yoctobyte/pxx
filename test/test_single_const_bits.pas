program test_single_const_bits;
{ The same defect as test_single_const_value.pas, asserted through the one shape
  XTENSA can run: the constant's BITS, printed as an integer.

  Writing a Single needs float formatting, which pulls in softfloat, which needs
  calloc -- and the xtensa backend emits no dynamic segment, so the value form of
  this test cannot be built for the target where the bug matters most. Reading
  the bits through a pointer needs none of that.

  0.5 is $3F000000 = 1056964608; -1.5 is $BFC00000 = -1077936128 signed. Both
  are target-independent, so a target that disagrees is wrong by construction.

  Measured on xtensa before the fix: `0` and `0`. Every Single CONSTANT on that
  target was zero -- pure Pascal, no C anywhere, no diagnostic.

  FPC IS NOT THE ORACLE HERE, and the reason is worth writing down because the
  output looks exactly like a disagreement: FPC prints 0 for all three of
  `p^`, `PInteger(@s)^` and `PInteger(@s)^` inline, while printing `s:0:4` as
  0.5000 in the same program. So FPC agrees about the VALUE and simply does not
  reflect it through the address -- an artifact of taking the address of a float
  local, not a claim about the constant. The oracle for this test is IEEE-754,
  which is not a matter of opinion: 0.5 is $3F000000 and -1.5 is $BFC00000. All
  six of our targets agree with that and with each other.
  bug-c-the-f-suffix-on-a-float-literal-is-ignored }
const
  S1: Single = 0.5;
  SNeg: Single = -1.5;
var
  s: Single;
  p: ^Integer;
begin
  s := S1;   p := @s; Writeln(p^);
  s := SNeg; p := @s; Writeln(p^);
end.
