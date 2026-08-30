program test_mgmt_operators_global_array_refused;
{ The same refusal as test_mgmt_operators_array_refused, for a GLOBAL rather
  than a proc local: globals are wrapped by WrapMainBodyManagementOps, a
  separate call into the same pass, and one arm being right has never implied
  the other here.

  It exists because the refusal it guards fired for years FOR THE WRONG REASON.
  The check read the symbol's RecName, which only AllocVar/AllocParam ever
  write — for an array the record id lives in ElemRecName — and it worked only
  because symbol slots are RECYCLED and the stale value happened to be the
  right record. When 4a3c88532 cleared that field on recycle, both arms went
  silent at once and an array of a managed record compiled with an Initialize
  that never runs.

  So a test that only asserts "this is refused" cannot tell a correct guard
  from a lucky one. What makes this pair worth having is that they now fail
  together and for a stated reason, and that the local arm was measured against
  a rebuild with the clear reverted: refused there too, on the accident.

  regression-test-core-test-mgmt-operators }
{$mode objfpc}{$H+}{$modeswitch advancedrecords}
type
  TFoo = record
    n: Integer;
    class operator Initialize(var a: TFoo);
  end;
class operator TFoo.Initialize(var a: TFoo);
begin a.n := 0; end;

var
  arr: array[0..1] of TFoo;
begin
  arr[0].n := 1;
  writeln(arr[0].n);
end.
