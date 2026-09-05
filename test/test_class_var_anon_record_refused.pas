{ MUST NOT COMPILE. An ANONYMOUS record has no type name to qualify a class var
  access with, so it cannot carry one. FPC refuses it too (terecs13c, a %FAIL
  conformance row that is NOT skip-listed, so it passes by refusal — this file
  is the reason that stays true).
  Asserted in the Makefile, which greps for the message. }
program test_class_var_anon_record_refused;
{$mode delphi}
var
  R: record
    class var
      TestField: Integer;
  end;
begin
end.
