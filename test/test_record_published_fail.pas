{ %FAIL-style negative: a `published` section in a record (terecs2).
  `published` exists for RTTI-driven streaming of an object; a record has no place in it.
  It used to be consumed and dropped, so the modifier silently meant nothing.
  See test/test_record_rules_ok.pas for what stays legal. }
program test_record_published_fail;
{$mode delphi}
type
  TFoo = record
  private
    F1: Integer;
  published
    F5: AnsiString;
  end;
begin
end.
