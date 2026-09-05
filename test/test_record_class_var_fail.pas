{ %FAIL-style negative: `class var` in a record that has no global storage to
  put it in. NARROWED 2026-09-05 by a11b2b18f, which implemented `class var` in
  a NAMED, top-level record -- fpc 3.2.2 accepts that under advancedrecords
  (implied by mode delphi), so the blanket refusal this file used to assert was
  the thing being fixed, not a rule being broken.

  A record has no per-instance metaclass, so what still fails is about the
  record's own identity rather than its contents: a type declared INSIDE a
  routine is not global and its class var's storage would be.
  The anonymous case is test_record_class_var_anon_fail.pas; the accepted case
  is test_record_class_var_ok.pas, and all three are wired together so the
  narrowing cannot drift back into a blanket answer in either direction. }
program test_record_class_var_fail;
procedure P;
type
  TLocal = record
  class var
    X: Integer;
  end;
begin
end;
begin
end.
