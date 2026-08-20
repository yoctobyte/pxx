program test_mgmt_operators_array_refused;
{ An ARRAY of a record with a management operator: FPC initializes and
  finalizes every element through recursive RTTI; pxx's per-symbol desugar
  reaches the variable, not its elements. Compiling this silently would give a
  declared invariant that simply never runs, so it is REFUSED and names the
  ticket instead — feature-pascal-management-operators-nested-and-array. }
{$mode objfpc}{$H+}{$modeswitch advancedrecords}
type
  TFoo = record
    n: Integer;
    class operator Initialize(var a: TFoo);
  end;
class operator TFoo.Initialize(var a: TFoo);
begin a.n := 0; end;

procedure P;
var arr: array[0..1] of TFoo;
begin
  arr[0].n := 1;
end;

begin
  P;
end.
