program test_single_const_value;
{ A Single CONSTANT's value, which on riscv32 was ZERO -- every one of them.

  A float constant carries the DOUBLE bit pattern whatever its declared type
  says (defs.inc, AN_FLOAT_LIT), so a backend that reads a tySingle constant has
  to NARROW it. riscv32's IR_CONST_INT took the low 32 bits instead, which is the
  low half of a double's mantissa: 0.5 read back as 0.0, and the four-element
  array as (0, 0, 0, 0). Silent, and only on that target.

  Found from the C side (bug-c-the-f-suffix-on-a-float-literal-is-ignored): C
  started typing `0.1f` as single, which routed a C literal down the same path a
  Pascal Single const had been using all along. The C defect was the visible one;
  this was underneath it, older, and reachable with no C in the program at all.

  Every row is target-independent, so a target that disagrees is wrong by
  construction. Row 6 asserts 1e30 by COMPARISON rather than by digits: it is the
  out-of-comfortable-range element DoubleBitsToSingleBits was written for, and
  its decimal expansion differs from FPC's for reasons that are Track F's and
  have nothing to do with this. }
const
  S1: Single = 0.5;
  SNeg: Single = -1.5;
var
  a: Single;
  b: Double;
  arr: array[0..3] of Single = (0.0, -1.5, 2.5, 1e30);
  i: Integer;
begin
  a := 2.5; b := a;
  Writeln('1 ', b:0:4);
  Writeln('2 ', S1:0:4);
  Writeln('3 ', SNeg:0:4);
  a := S1 * 3.0;
  Writeln('4 ', a:0:4);
  Write('5');
  for i := 0 to 2 do Write(' ', arr[i]:0:2);
  Writeln;
  Writeln('6 ', arr[3] > 9.9e29);
end.
