{ %FAIL-style negative: .member on a plain Pointer.

  This used to COMPILE and evaluate to the pointer itself, so a typo on a
  pointer-typed receiver became a silent no-op
  (bug-pascal-member-access-on-pointer-silently-accepted). A pointer to a RECORD
  is auto-dereferenced instead (test_forward_ptr_record_field.pas); a bare
  Pointer has no member namespace at all. }
program test_pointer_member_fail;
var
  q: Pointer;
begin
  q := nil;
  writeln(PtrUInt(q.NoSuchThing));
end.
