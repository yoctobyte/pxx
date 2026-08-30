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
  bug-c-the-f-suffix-on-a-float-literal-is-ignored

  ROWS 3..8 ARE THE SHAPES THE IMMEDIATE PATH CANNOT REACH, and they are here
  because the fix above was asserted complete from row 1 alone. A tySingle
  carrying DOUBLE bits is a property of the CONSTANT, not of the path that
  materialises it, so "the immediate path was the whole bug" is a claim about
  every other path and cannot be tested by the immediate path. Measured after
  the fix on xtensa, riscv32 and x86-64, all three agreeing: the data emitter
  was already narrowing correctly (TryBakeConstArrayIntoData calls
  DoubleBitsToSingleBits), so there is no second leak -- but that was a
  measurement, not a deduction, and it is pinned here so it stays one. }
type
  TRSingle = record a: Single; end;
const
  S1: Single = 0.5;
  SNeg: Single = -1.5;
  ARR: array[0..1] of Single = (0.5, -1.5);
  REC: TRSingle = (a: 0.5);
var
  s: Single;
  p: ^Integer;

procedure Show(v: Single);
{ A literal ARGUMENT: the const is materialised into the parameter slot, which
  on the two soft-float ILP32 targets is a 32-bit register and on the rest is
  not -- the one row whose lowering differs per target while its answer must
  not. }
var q: ^Integer;
begin q := @v; Writeln(q^); end;

begin
  s := S1;      p := @s; Writeln(p^);   { 1: immediate, the original subject }
  s := SNeg;    p := @s; Writeln(p^);   { 2: immediate, negative }
  s := ARR[0];  p := @s; Writeln(p^);   { 3: data section, element }
  s := ARR[1];  p := @s; Writeln(p^);   { 4: data section, negative element }
  s := REC.a;   p := @s; Writeln(p^);   { 5: data section, record field }
  p := @ARR[0];           Writeln(p^);  { 6: data section, read in place }
  s := 0.25 + 0.25; p := @s; Writeln(p^); { 7: const-folded expression }
  Show(0.5);                            { 8: literal argument }
end.
