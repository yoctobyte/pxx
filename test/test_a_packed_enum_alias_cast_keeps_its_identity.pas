program test_a_packed_enum_alias_cast_keeps_its_identity;
{$PACKENUM 1}
{ The alias-door twin of test_the_alias_cast_door_answers_like_the_builtin_one,
  at the OTHER value of the axis that file holds constant.

  An enum's storage kind is tyInteger by default and tyUInt8 under a packed
  enum directive. The alias door's enum-identity rule was written as
  `if kind = tyInteger then take the id`, which is a correct test only while
  every enum IS tyInteger -- so `type TS2 = TSmall; TS2(1)` printed 1 under this
  directive where `TSmall(1)` printed sB, and printed sB correctly without it.

  The sibling door's comment had already predicted this in exactly those words,
  and the row set that cleared the first half of the fix varied the DOOR and
  held the directive at its default, so no row in it could have seen the second
  half. That is why this is a FILE and not four more rows in that one: a packed
  enum directive is file-scoped, so the two values of the axis cannot coexist in
  one program, and folding them together would silently drop the default half.

  The identity now comes from the alias table's own column, which answers "is
  this an enum" without asking anything about the kind -- so narrowing a kind
  again cannot re-break it. The SizeOf rows are the controls: they assert the
  directive is actually in force, since every value row would read identically
  if it were not.

  fpc 3.2.2 is the oracle. refactor-p-five-dispatch-sites-for-one-named-type-cast }
type
  TSmall = (sA, sB, sC);
  TS2    = TSmall;
var i: LongInt;
begin
  i := 1;
  WriteLn('value builtin ', TSmall(i));
  WriteLn('value alias   ', TS2(i));
  WriteLn('size  builtin ', SizeOf(TSmall(i)));
  WriteLn('size  alias   ', SizeOf(TS2(i)));
  WriteLn('size  decl    ', SizeOf(TSmall));
end.
