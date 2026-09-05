{ A class property whose accessor is a CLASS VAR rather than a static getter.

  `class property V: T read FV write FV` over `class var FV: T` is what FPC
  calls a static class property, and pxx could not reach it: the class-property
  access path built the accessor name from the METHOD slots and called
  FindUMeth, so a class property could be backed by a static method and by
  nothing else. Both declaration parsers put any accessor that is not an
  instance FIELD into the method slot, so a class var's name arrived there and
  the diagnostic named the lookup that failed rather than the one that was
  missing (`class property accessor not found: FV`).

  BOTH DECLARING TYPE KINDS ARE HERE ON PURPOSE. The two spellings failed
  differently and that is why this read as two bugs: a RECORD was refused while
  PARSING the declaration, a CLASS parsed and failed at the USE. One cause, two
  phases — so a test covering one kind would have passed while the other stayed
  broken.

  THE SHARING IS THE ASSERTION. A property backed by an instance field would
  compile every line here; writing through the type and reading it back after a
  second write is what shows one slot behind the property. Expected output is
  fpc 3.2.2's own.

  WHAT IS NOT COVERED HERE is every spelling that does not name the TYPE:
  unqualified, Self-qualified, instance-qualified and with-scoped. Those were
  five further sites with the identical missing arm and they landed the same
  day, in test_class_property_through_an_instance.pas — which is also where the
  SHARING is proved across two instances, something this file cannot do because
  the type spelling has no instance to be wrong about.
  bug-p-a-class-property-cannot-be-backed-by-a-class-var }
program test_class_property_backed_by_a_class_var;
{$mode delphi}

type
  TCls = class
  private
    class var FV: LongInt;
  public
    class property V: LongInt read FV write FV;
  end;

  TRec = record
  class var
    FVal: LongInt;
  class property Val: LongInt read FVal write FVal;
  end;

begin
  { class: write and read through the property }
  TCls.V := 9;
  WriteLn(TCls.V);

  { the property and the class var are one slot, not two }
  TCls.FV := 12;
  WriteLn(TCls.V);
  TCls.V := 13;
  WriteLn(TCls.FV);

  { record: the spelling that used to be refused at the declaration }
  TRec.Val := 41;
  WriteLn(TRec.Val);
  TRec.FVal := 42;
  WriteLn(TRec.Val);

  { two types, two slots }
  WriteLn(TCls.V, ' ', TRec.Val);
end.
