program test_record_visibility_strict_fail;
{$mode objfpc}{$modeswitch advancedrecords}
{ %FAIL under --strict-visibility: a strict private RECORD member is type-scoped,
  so code outside the record cannot reach it. The class twin of this row
  (test_member_visibility_strict_fail) has passed since the flag landed; the
  record shape compiled silently until 2026-09-09, because ParseRecordFields
  consumed the section marker and stamped every member VIS_PUBLIC.
  Compiles under the lax default; rejected under --strict-visibility. }
type
  TRec = record
  strict private
    FSecret: integer;
  public
    procedure Init;
  end;

procedure TRec.Init;
begin
  FSecret := 1;     { the record's OWN method: legal, and must stay legal }
end;

var r: TRec;
begin
  r.Init;
  r.FSecret := 9;   { strict private of a record, from outside it -> illegal }
  WriteLn(r.FSecret);
end.
