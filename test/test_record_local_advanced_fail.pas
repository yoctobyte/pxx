{ %FAIL-style negative: advanced members on a record declared INSIDE a routine
  (terecs12a/12b; the anonymous `var R: record ... end` form is the same rule, terecs13*).
  A method there could never be given an implementation — there is nowhere for it to live.
  pxx used to accept the whole advanced surface and register methods that could never be
  defined. Plain FIELDS remain legal in both forms — see test/test_record_rules_ok.pas. }
program test_record_local_advanced_fail;
{$mode delphi}
procedure Test;
type
  TRecord = record
  var
    TestField: Integer;
    property TestProperty: Integer read TestField;
  end;
begin
end;
begin
end.
