program test_mgmt_operators_multidim_array_refused;
{ A MULTI-DIMENSIONAL array of a record with a management operator, still
  REFUSED — the second arm of the same refusal test_mgmt_operators_array_refused
  covers, and a separate fixture because it fails a DIFFERENT clause of
  SymIsLoopableManagedArray. A 2-D array has a fixed ArrLen, so the dynamic
  fixture cannot reach this arm and a regression here would be invisible to it.

  The loop AppendManagedArrayOps synthesises is one-dimensional. Getting the 2-D
  case right is not "run it over the flat extent": that would be correct for the
  element ORDER but wrong the moment the desugar has to build the index node,
  which is per-dimension.

  feature-pascal-management-operators-nested-and-array }
{$mode objfpc}{$H+}{$modeswitch advancedrecords}
type
  TFoo = record
    n: Integer;
    class operator Initialize(var a: TFoo);
  end;
class operator TFoo.Initialize(var a: TFoo);
begin a.n := 0; end;

procedure P;
var arr: array[0..1, 0..1] of TFoo;
begin
  arr[0,0].n := 1;
end;

begin
  P;
end.
