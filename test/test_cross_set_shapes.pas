program test_cross_set_shapes;
{ The set shapes test_cross_sets does not reach: every comparison direction,
  symmetric difference, an out-of-range member, the empty set, a nested
  expression (which is what shares the per-body locals), and a byte at the top
  of the 32-byte mask. }
type TS = set of Byte;
var a, b, c, e: TS; i: Integer; n: Byte;
begin
  a := [1, 3, 5];
  b := [1, 3, 5, 7];
  e := [];
  WriteLn('le    ', a <= b, ' ', b <= a, ' ', a <= a);
  WriteLn('lt    ', a < b, ' ', b < a, ' ', a < a);
  WriteLn('ge    ', b >= a, ' ', a >= b, ' ', a >= a);
  WriteLn('gt    ', b > a, ' ', a > b, ' ', a > a);
  WriteLn('eq    ', a = b, ' ', a = a, ' ', a <> b);
  c := a >< b;      WriteLn('symd  ', 7 in c, ' ', 1 in c);
  c := a + b;       WriteLn('union ', 7 in c, ' ', 1 in c);
  c := b - a;       WriteLn('diff  ', 7 in c, ' ', 1 in c);
  c := a * b;       WriteLn('inter ', 1 in c, ' ', 7 in c);
  WriteLn('empty ', e = [], ' ', 1 in e, ' ', e <= a);
  n := 255; a := a + [255];  WriteLn('top   ', n in a, ' ', 254 in a);
  i := 300;         WriteLn('oor   ', i in a);
  i := -1;          WriteLn('neg   ', i in a);
  WriteLn('nest  ', 3 in (a * b) + (b - a), ' ', 7 in (a * b));
end.
