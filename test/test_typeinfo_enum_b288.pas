{ `TypeInfo(TEnum)` + TypInfo's enum reflection: GetEnumName / GetEnumValue.

  The compiler already emits an RTTI blob per enum type -- {name, count, names[]} -- for
  enum-typed published properties. TypeInfo yields its address (through a data-ref sentinel,
  since the offset is only known after EmitRTTI), and lib/rtl/typinfo reads it.

  TypeInfo of a CLASS or RECORD is deliberately REFUSED at compile time: pxx's RTTI blobs
  are our layout and will never match FPC's TTypeData, so handing one back would be silently
  misread. Enum names are what real code actually asks TypInfo for -- fpjson prints its JSON
  type names this way -- and those we have exactly. }
program test_typeinfo_enum_b288;
uses typinfo;
type
  TColor = (Red, Green, Blue);
  TJSONtype = (jtUnknown, jtNumber, jtString, jtBoolean, jtNull, jtArray, jtObject);
var
  c: TColor;
  i: Integer;
begin
  writeln('count: ', GetEnumNameCount(TypeInfo(TColor)));
  for c := Red to Blue do
    writeln('  ', Ord(c), ' = ', GetEnumName(TypeInfo(TColor), Ord(c)));
  writeln('value of Green: ', GetEnumValue(TypeInfo(TColor), 'Green'));
  writeln('value of green (ci): ', GetEnumValue(TypeInfo(TColor), 'green'));
  writeln('value of nope: ', GetEnumValue(TypeInfo(TColor), 'nope'));
  writeln('out of range: [', GetEnumName(TypeInfo(TColor), 9), ']');
  writeln('--- a second enum type:');
  for i := 0 to GetEnumNameCount(TypeInfo(TJSONtype)) - 1 do
    write(GetEnumName(TypeInfo(TJSONtype), i), ' ');
  writeln;
end.
