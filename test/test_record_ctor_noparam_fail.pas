{ %FAIL-style negative: a record constructor with no MANDATORY parameter (terecs17/17a).
  A record is a value that always exists, so a parameterless ctor is indistinguishable from
  its default state. A lone parameter WITH a default is the same hole spelled differently —
  it is still callable with none — which is why the check counts mandatory parameters.
  See test/test_record_rules_ok.pas: a ctor WITH a real parameter is fine. }
program test_record_ctor_noparam_fail;
{$mode delphi}
type
  TRec = record
    X: Integer;
    constructor Create(I: Integer = 0);
  end;
constructor TRec.Create(I: Integer = 0);
begin
end;
begin
end.
