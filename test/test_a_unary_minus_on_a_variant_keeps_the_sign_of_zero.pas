program test_a_unary_minus_on_a_variant_keeps_the_sign_of_zero;
{ `-v` on a Variant holding +0.0 answered +0.0: the lowering rewrote it as
  `0 - v`, and IEEE gives 0 - (+0.0) = +0.0. A plain Double's `-d` gives -0.0
  and so does fpc's Variant. Pascal now rewrites to `v * -1`. The other rows
  show that every payload keeps its value. Each line matches fpc 3.2.2.
  bug-a-unary-minus-on-a-variant-loses-the-sign-of-zero-because-the-correct-helper-is-not-wired }
{$mode objfpc}
uses variants;
var v, w: Variant; d: Double; i: Int64;
begin
  v := 0.0; w := -v; d := w; WriteLn('-(+0.0) sign ', PQWord(@d)^ shr 63);
  v := d;   w := -v; d := w; WriteLn('-(-0.0) sign ', PQWord(@d)^ shr 63);
  v := 2.5; WriteLn(-v);
  v := 7; WriteLn(-v);
  v := '5'; WriteLn(-v);
  i := Low(Int64); v := i; WriteLn(-v);
end.
