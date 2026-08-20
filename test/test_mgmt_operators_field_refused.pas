program test_mgmt_operators_field_refused;
{ ...and the same for a record that merely CONTAINS one in a field. Same
  reason, same ticket: the desugar has no field path, FPC's RTTI walk does.
  feature-pascal-management-operators-nested-and-array }
{$mode objfpc}{$H+}{$modeswitch advancedrecords}
type
  TFoo = record
    n: Integer;
    class operator Initialize(var a: TFoo);
  end;
  TBar = record
    f: TFoo;
    k: Integer;
  end;
class operator TFoo.Initialize(var a: TFoo);
begin a.n := 0; end;

procedure P;
var b: TBar;
begin
  b.k := 1;
end;

begin
  P;
end.
