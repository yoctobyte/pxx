{ %FAIL-style negative: Default() on an UNSPECIALIZED generic template.

  A template is not a type — it has no size and no zero value until it is
  specialized — so Default(TBox) is undefined. pxx used to accept it and hand back a
  zero of no particular type (tdefault11/12).

  `Default(TBox<Integer>)` (delphi) and `Default(specialize TBox<Integer>)` (objfpc)
  remain legal: the check only fires on a bare template name not followed by '<'. }
program test_default_unspecialized_generic_fail;
{$mode objfpc}
type
  generic TBox<T> = class
    Data: T;
  end;
var
  o: TObject;
begin
  o := Default(TBox);
  writeln(PtrUInt(o));
end.
