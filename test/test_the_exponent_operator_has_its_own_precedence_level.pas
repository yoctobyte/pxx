{ Pascal `**`. It had no lexer token at all -- `operator ** (a, b: T): T` arrived
  as two tkStar and died on `expected ':'` -- and it is a precedence LEVEL of its
  own, between the multiplicative level and the factor.

  Every precedence and associativity row below was measured against fpc 3.2.2
  with the math unit before it was written down, not derived from a table:
  `2 ** 3 ** 2` is 64, so it associates LEFT; `2 * 3 ** 2` is 18 and
  `2 ** 3 + 1` is 9, so it binds tighter than both `*` and `+`.

  `**` HAS NO BUILT-IN MEANING, here or in fpc's core language -- fpc's math unit
  DECLARES `operator **` for floats. So every row below is an overload call, the
  scalar rows included, and an unoverloaded `a ** b` is a diagnostic in both
  compilers. That is also why a scalar `**` overload is allowed where a scalar
  `*` one is refused: there is no predefined operation for it to shadow, and no
  arithmetic fallback for a scalar-keyed table entry to poison.

  The last four rows are the controls: `*`, `+` and `-` must be untouched by the
  new level, and the record operator must still reach a `class operator`. }
{$mode objfpc}
{$modeswitch advancedrecords}
program test_the_exponent_operator_has_its_own_precedence_level;

type
  TFoo = record
    v: LongInt;
    class operator ** (a, b: TFoo): TFoo;
  end;

operator ** (a, b: Integer) r: Integer;
var i: Integer;
begin
  r := 1;
  for i := 1 to b do r := r * a;
end;

class operator TFoo.** (a, b: TFoo): TFoo;
begin
  Result.v := a.v * 100 + b.v;
end;

var
  p, q: Integer;
  x, y, z: TFoo;
begin
  WriteLn('2**3**2  = ', 2 ** 3 ** 2);
  WriteLn('2*3**2   = ', 2 * 3 ** 2);
  WriteLn('2**3*2   = ', 2 ** 3 * 2);
  WriteLn('2**3+1   = ', 2 ** 3 + 1);
  WriteLn('1+2**3   = ', 1 + 2 ** 3);
  p := 3; q := 4;
  WriteLn('p**q     = ', p ** q);
  WriteLn('p**2+1   = ', p ** 2 + 1);
  x.v := 4; y.v := 5;
  z := x ** y;
  WriteLn('rec      = ', z.v);
  WriteLn('star     = ', 2 * 3, ' ', 4 * 5);
  WriteLn('plus     = ', 2 + 3, ' ', 7 - 2);
  WriteLn('mixed    = ', 2 + 3 * 4, ' ', (2 + 3) * 4);
  WriteLn('div/mod  = ', 17 div 5, ' ', 17 mod 5);
end.
