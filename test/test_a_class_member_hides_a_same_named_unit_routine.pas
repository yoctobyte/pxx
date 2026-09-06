{ A class's OWN MEMBER hides a routine from an outer scope — that is the rule,
  and pxx applied it to METHODS only. A FIELD, PROPERTY or CLASS VAR whose name
  matched a routine in a used unit lost the name to the routine, and stopped
  being a variable at all:

    error: by-reference argument must be a variable      { the field case }

  a diagnostic about the ARGUMENT'S FORM for a defect in name resolution, which
  is why it reads as unrelated. fcl-passrc's pastree.pp:2397 is the live case —
  `ReleaseAndNil(TPasElement(ExceptObject))` on a field named `ExceptObject`,
  against `function ExceptObject: TObject` in lib/rtl/sysutils.pas.

  THE ROWS ARE THE MEMBER KINDS, and each asserts a VALUE only the member can
  produce, because the failure mode is not a refusal in every arm: a read-only
  use of a shadowed PROPERTY whose getter returns the same kind as the routine
  compiles either way and prints the WRONG SOURCE'S answer. `ExceptObject`
  returns nil outside an exception handler, so the field row is asserted at a
  non-nil value and the property row at a value the routine cannot return.

  CLASS CONST IS DELIBERATELY NOT A ROW. It is the fifth member kind and it is
  excluded from the fix for the reason the nested-routine scan excludes it:
  `<instance>.K` is refused generally, so routing the name to member dispatch
  would trade one wrong answer for a different one
  (bug-p-a-class-const-is-unreachable-through-an-instance-receiver).

  THE LAST ROW IS THE CONTROL. A name that is NOT a member of this class must
  still reach the unit routine from inside a method — otherwise the fix is not
  "the member wins", it is "nothing from a used unit is callable in a method".
  bug-p-a-class-field-loses-its-name-to-a-same-named-unit-routine }
{$mode objfpc}
program test_a_class_member_hides_a_same_named_unit_routine;
uses sysutils;

type
  TBox = class
    N: Integer;
  end;

  TC = class
  private
    FTrim: AnsiString;
    function GetUpperCase: AnsiString;
  public
    ExceptObject: TBox;            { vs sysutils `function ExceptObject: TObject` }
    class var StrToInt: Integer;   { vs sysutils `function StrToInt(...)`         }
    property UpperCase: AnsiString read GetUpperCase;   { vs sysutils UpperCase }
    procedure Run;
  end;

function TC.GetUpperCase: AnsiString;
begin
  Result := 'from-the-property';
end;

procedure Clear(var b: TBox);
begin
  if b <> nil then begin b.N := b.N + 1; b := nil; end;
end;

procedure TC.Run;
begin
  { FIELD: must be an lvalue, and a `var` argument through a class typecast is
    exactly how pastree.pp uses it }
  ExceptObject := TBox.Create;
  ExceptObject.N := 41;
  WriteLn('field n   = ', ExceptObject.N);
  Clear(TBox(ExceptObject));
  WriteLn('field nil = ', ExceptObject = nil);

  { PROPERTY: sysutils.UpperCase takes an argument, so the bare name could only
    ever have been the property -- and the value says which one answered }
  WriteLn('property  = ', UpperCase);

  { CLASS VAR: same name as a sysutils FUNCTION, read and written as a variable }
  StrToInt := 7;
  StrToInt := StrToInt + 1;
  WriteLn('classvar  = ', StrToInt);

  { CONTROL: a sysutils routine this class does NOT declare must still resolve }
  FTrim := Trim('  padded  ');
  WriteLn('unit call = [', FTrim, ']');
end;

var c: TC;
begin
  c := TC.Create;
  c.Run;
end.
