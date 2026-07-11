{ %FAIL-style negative: a by-value field of the enclosing record type is
  infinitely recursive (terecs9). Class self-references (pointers) stay legal
  — see test companion program below in Makefile. }
program test_record_self_field_fail;
type
  TFoo = record
    FFoo: TFoo;
  end;
begin
end.
