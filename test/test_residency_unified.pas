{ -O3 unified loop residency (feature-opt-pxx-internal-abi-unified-residency):
  4 hot ints (r12-r15 / x19-x24) + 3 hot doubles (xmm8-13 / d8-d13) resident in
  ONE loop body that calls an internal helper every iteration — under the pxx
  internal ABI the residents are callee-saved save-iff-used, so the call must
  not disturb them. The helper has its own float residents (nested save-iff-
  used). Output must be identical at every -O level (optdiff sweeps this). }
program test_residency_unified;

function Wobble(t: Double): Double;
var w: Double;
    k: Integer;
begin
  { own hot double: claims xmm8/d8 inside the callee while the caller's
    residents live in the same pool — exercises the save/restore pairing }
  w := t;
  for k := 1 to 3 do
    w := w * 0.5 + 1.0;
  Wobble := w;
end;

procedure Run;
var a, b, c, d: Int64;
    x, y, z: Double;
    i: LongInt;
begin
  a := 1; b := 2; c := 3; d := 5;
  x := 0.5; y := 1.25; z := 0.0;
  for i := 1 to 200000 do
  begin
    a := a + i;
    b := b xor a;
    c := c + (b and 1023);
    d := d + (a xor c);
    x := x + 0.00001;
    y := y * 0.99999 + x * 0.00001;
    z := z + Wobble(x) * 0.00001 + y * 0.00001;
  end;
  writeln('a=', a);
  writeln('b=', b);
  writeln('c=', c);
  writeln('d=', d);
  writeln('x=', Round(x * 1000000));
  writeln('y=', Round(y * 1000000));
  writeln('z=', Round(z * 1000000));
end;

begin
  Run;
end.
