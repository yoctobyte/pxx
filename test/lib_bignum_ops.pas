program lib_bignum_ops;

{ Golden test for the bignum operator layer — and the managed-record
  operator-temp workout: TBigInt holds a dynarray, so every chained operator
  expression routes managed temporaries through the operator call path
  (`c := a * b + a` = temp from *, consumed by +). Expected values computed
  independently (Python ints). }

uses bignum;

var
  a, b, c, q, r, p, f, k: TBigInt;
  n: Integer;
begin
  { chained temporaries on a managed record: c := a * b + a }
  a := BigFromStr('10000000000000000000000000000000000012345');
  b := BigFromStr('99999999999999999993');
  c := a * b + a;
  writeln('chain=', BigToStr(c));

  { div/mod identity on the chain result: c = (c div b)*b + (c mod b) }
  q := c div b;
  r := c mod b;
  writeln('div=', BigToStr(q));
  writeln('mod=', BigToStr(r));
  if q * b + r = c then writeln('identity=yes') else writeln('identity=no');

  { factorial(50) with operator * in the loop }
  f := BigFromInt(1);
  for n := 2 to 50 do
    f := f * BigFromInt(n);
  writeln('f50=', BigToStr(f));

  { 2^512 by repeated squaring: p := p * p, 9 times from 2 }
  p := BigFromInt(2);
  for n := 1 to 9 do
    p := p * p;
  writeln('p512=', BigToStr(p));

  { sign flips around zero }
  a := BigFromInt(12345);
  b := BigFromStr('1000000000000000000000000000000');
  writeln('negsub=', BigToStr(a - b));
  writeln('backagain=', BigToStr(a - b + b));
  if a - a = BigFromInt(0) then writeln('zero=yes') else writeln('zero=no');

  { comparison matrix on -2, 0, 3 }
  a := BigFromInt(-2); k := BigFromInt(0); b := BigFromInt(3);
  writeln('lt=', a < k, ' ', k < b, ' ', b < a);
  writeln('le=', a <= a, ' ', a <= b, ' ', b <= k);
  writeln('gt=', b > k, ' ', k > a, ' ', a > b);
  writeln('ge=', k >= k, ' ', b >= a, ' ', a >= k);
  writeln('eq=', a = a, ' ', a = b);
  writeln('ne=', a <> b, ' ', k <> k);

  { negative div/mod: trunc-toward-zero, sign(r) = sign(a) }
  a := BigFromInt(-7); b := BigFromInt(3);
  writeln('negdiv=', BigToStr(a div b), ' ', BigToStr(a mod b));
  if (a div b) * b + (a mod b) = a then writeln('negidentity=yes') else writeln('negidentity=no');
end.
