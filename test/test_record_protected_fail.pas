{ %FAIL-style negative: a `protected` section in a record (terecs19).
  `protected` presupposes inheritance, and records do not inherit. Parse-and-dropped before.
  See test/test_record_rules_ok.pas. }
program test_record_protected_fail;
{$mode objfpc}{$modeswitch advancedrecords}
type
  TRecord = record
  protected
    f2: LongInt;
  end;
begin
end.
