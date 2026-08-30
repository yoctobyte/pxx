{ An `object` type cannot have an ANCESTOR. pxx lowers `object` as a value type
  with no VMT, so inheritance would have to build a second object model beside
  the class one -- deliberately out of scope, and refused loudly rather than
  accepted-and-ignored. Use a class to inherit.
  bug-p-object-value-types-standard-meaning }
program test_object_value_ancestor_error;
type
  TBase = object
    X: Integer;
  end;
  TDerived = object(TBase)
    Y: Integer;
  end;
var d: TDerived;
begin
  d.X := 1;
end.
