{ TObject.UnitName — the DECLARING unit's name, the last member of
  feature-pascal-builtin-tobject-class that was still PXX-REJECT.

  Three answers, and each is a different source of the string:
    - a class declared in a unit      -> that unit's name
    - a class declared in the program -> the PROGRAM's name (measured against
      fpc 3.2.2: it does not answer 'System' or '' for these)
    - TObject itself                  -> 'System'

  The value was already tracked (UClsUnitIdx is the Strs[] index of the
  declaring unit, -1 for the main program); what was missing was a word in the
  class RTTI blob to put it in and an accessor to read it. TObject's 'System'
  is stamped in rtti_emit rather than by faking a UClsUnitIdx, because that
  field is the visibility scope and a fake unit index would quietly change who
  may touch a private member.

  Asserted on an INSTANCE and on a CLASS REFERENCE, and through an inherited
  answer (TDerived declares nothing of its own), because those are three
  different paths into the same blob word.

  Expected output is fpc 3.2.2's own (-Mobjfpc -O1).
  feature-pascal-builtin-tobject-class }
{$mode objfpc}{$H+}
program test_tobject_unitname;
uses tobject_unitname_unit;
type
  TInProgram = class(TObject)
    Z: Integer;
  end;
var
  o: TObject;
  p: TInUnit;
  d: TDerived;
  q: TInProgram;
begin
  o := TObject.Create;
  p := TInUnit.Create;
  d := TDerived.Create;
  q := TInProgram.Create;
  writeln('[', o.UnitName, ']');            { System }
  writeln('[', p.UnitName, ']');            { the unit }
  writeln('[', d.UnitName, ']');            { same unit, via a descendant }
  writeln('[', q.UnitName, ']');            { the program }
  writeln('[', TInUnit.UnitName, ']');      { class reference, not an instance }
  writeln('[', TObject.UnitName, ']');
  writeln('[', TObject.ClassName, ']');     { the neighbouring blob word still works }
  writeln('[', p.ClassName, ']');
  o.Free; p.Free; d.Free; q.Free;
end.
