{ %FAIL-style negative: an undefined FIELD on a record must error, not compile
  at offset 0 as tyInteger and read garbage
  (bug-pascal-undefined-field-on-empty-record-compiles). }
program test_undefined_field_fail;
type
  TR0 = record
  end;
var
  r0g: TR0;
  x: longint;
begin
  x := r0g.someundefinedfield;
  writeln(x);
end.
