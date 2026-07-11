{ %FAIL-style negative: enum vs pointer comparison (toperatorerror). }
program test_enum_pointer_compare_fail;
type TEnum = (ea);
var p: Pointer; e: TEnum;
begin
  if e <> p then ;
end.
