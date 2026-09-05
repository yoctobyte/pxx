{ NEGATIVE CONTROL, the harder half: the name IS declared and IS a constant, and
  is still not a string. `FindStrConst` holds only untyped STRING constants, so
  an Integer const must not satisfy a string initialiser. This is the row that
  fails if the guard is ever loosened from "is a string const" to "is an
  identifier". }
program test_typed_const_named_wrongkind_fail;
const
  n1 = 7;
  X: ShortString = n1;
begin
  WriteLn(X);
end.
