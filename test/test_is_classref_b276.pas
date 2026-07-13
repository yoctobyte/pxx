{ `E is <class-reference VALUE>`: the class to test against known only at runtime --
  a TClass variable, param or field. fpcunit's TTestCase.RunBare does

      if not (E is FExpectedException) then ...

  where FExpectedException: TClass is a FIELD.

  AN_IS_TEST carries a compile-time class INDEX and cannot express this, but the test
  is exactly InheritsFrom on the instance's blob:

      E is cr   ==   __pxxInheritsFrom(rtti_of(E), cr)

  The compile-time form (`E is EMid`, a class NAME) keeps its own path and is asserted
  here too, so the new branch cannot quietly capture it. }
program test_is_classref_b276;
type
  EBase = class end;
  EMid = class(EBase) end;
  ELeaf = class(EMid) end;
  EOther = class end;
  TH = class
    Expected: TClass;                 { a class-reference FIELD, as in fpcunit }
    function Matches(e: EBase): Boolean;
  end;
function TH.Matches(e: EBase): Boolean;
begin
  Result := e is Expected;            { runtime class reference, via implicit Self }
end;
var h: TH; cr: TClass; l: ELeaf;
begin
  h := TH.Create;
  l := ELeaf.Create;
  h.Expected := EMid;
  writeln('leaf is mid (field): ', h.Matches(l));
  h.Expected := EOther;
  writeln('leaf is other (field): ', h.Matches(l));
  { a local TClass variable }
  cr := EBase;
  writeln('leaf is base (var): ', l is cr);
  cr := EOther;
  writeln('leaf is other (var): ', l is cr);
  { the compile-time form must still work }
  writeln('leaf is EMid (name): ', l is EMid);
  writeln('leaf is EOther (name): ', l is EOther);
end.
