{ -O3 reads a register-resident Double straight from its xmm8..13 register as a
  float-tree operand, and stores a fused tree (or a plain copy) straight into the
  target's register. Before, each operand went through xmm0 and each store through
  rax and xmm0, and that copy chain was the largest remaining gap to fpc on
  mandelbrot (2.09x -> 1.35x).
  feature-opt-double-code-is-2-to-4x-fpc-and-o3-already-halves-it

  The make row compares -O3 against -O0. Every operator has a resident on the RIGHT,
  and the non-commutative ones (- and /) would print a different value if the
  operands were swapped. The loop makes the values loop-carried, so they are
  residency candidates. Six locals fill the resident pool exactly, which also
  exercises a leaf that did NOT get a register (the param `k`). }
program test_o3_float_resident_operands;

function Mix(k: Double; n: Integer): Double;
var a, b, c, d, e, f: Double; i: Integer;
begin
  a := 1.5; b := 0.25; c := 3.0; d := 7.0; e := 0.0; f := 2.0;
  for i := 1 to n do
  begin
    e := a - b;          { resident right operand of - }
    c := d / f;          { resident right operand of / }
    d := c * b + a;      { tree into a resident }
    a := e;              { resident-to-resident copy }
    b := b + k - f / d;  { non-resident leaf in the tree }
    f := f - a;          { in-place shape }
  end;
  Mix := a * 1000000 + b * 1000 + c + d / 1000 + e + f;
end;

var r: Double;
begin
  r := Mix(0.125, 7);
  WriteLn(r:0:6);
  r := Mix(-0.5, 3);
  WriteLn(r:0:6);
end.
