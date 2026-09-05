{ NEGATIVE CONTROL for test_typed_const_from_named_const.pas: an initialiser
  that accepts a NAMED string constant must still refuse a name that is not one.
  Undeclared here; the sibling _wrongkind_ file covers "declared, wrong type".
  Without these two rows the fix could have replaced a wrong error with no error
  and every positive row would still pass. }
program test_typed_const_named_undeclared_fail;
const
  X: ShortString = nosuch;
begin
  WriteLn(X);
end.
