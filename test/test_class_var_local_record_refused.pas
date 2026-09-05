{ MUST NOT COMPILE. A record declared in a LOCAL type section cannot carry a
  class var: the slot's storage is global and the type is not. FPC refuses it
  too (terecs12c, a %FAIL conformance row that is NOT skip-listed, so it passes
  by refusal — this file is the reason that stays true).
  Asserted in the Makefile, which greps for the message. }
program test_class_var_local_record_refused;
{$mode delphi}
procedure Test;
type
  TRecord = record
  class var
    TestField: Integer;
  end;
begin
end;
begin
  Test;
end.
