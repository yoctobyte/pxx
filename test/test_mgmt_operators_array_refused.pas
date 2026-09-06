program test_mgmt_operators_array_refused;
{ A DYNAMIC array of a record with a management operator, still REFUSED.

  This fixture used to assert the same about a FIXED array, and that expired
  when the loop landed — a test whose whole claim is "we do not support X" goes
  red the day someone implements X, and the repair is to re-aim it at the part
  that is still true rather than to delete it. What is still true is the reason:
  the desugar needs BOUNDS IT CAN READ HERE. A fixed array carries them on the
  symbol (ConstVal is the low bound, ArrLen the extent); a dynamic array's
  extent is a runtime length, so the loop would have to call Length() and the
  pass has no model for that yet.

  Its sibling test_mgmt_operators_multidim_array_refused covers the other half
  of the same error, which is a DIFFERENT condition on the same predicate
  (SymArrNDims, not ArrLen) and would not fail with this one.

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
var arr: array of TFoo;
begin
  SetLength(arr, 2);
  arr[0].n := 1;
end;

begin
  P;
end.
