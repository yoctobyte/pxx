program test_mgmt_operators_array_refused;
{ A DYNAMIC array of a record with a management operator, still REFUSED.

  This fixture used to assert the same about a FIXED array, and that expired
  when the loop landed — a test whose whole claim is "we do not support X" goes
  red the day someone implements X, and the repair is to re-aim it at the part
  that is still true rather than to delete it.

  ITS SIBLING HAS SINCE EXPIRED TOO. test_mgmt_operators_multidim_array_refused
  held the 2-D half of this refusal and was retired on 2026-09-07, when a
  multi-dimensional fixed array started being walked flat; that shape lives in
  test_mgmt_operators_multidim_array now, as a POSITIVE row. Three expiries in
  this family, which is why none of them get deleted on sight.

  What is still true here is a different reason from the one this header used to
  give. It said the desugar "needs bounds it can read" and that a dynamic array
  would need a call to Length(). MEASURED 2026-09-07 against fpc 3.2.2, that is
  not where the work goes at all: Initialize runs INSIDE SetLength on the
  elements that come into existence, Finalize inside it on the ones that stop,
  and only the survivors are finalized at scope exit. A scope-entry loop over
  Length() would initialize ZERO elements — a dynamic array is empty at
  declaration — and would never see one created later.

  So this arm is not a missing loop in this pass; it needs a record RTTI
  descriptor that SetLength can consult.
  feature-a-record-rtti-descriptors-for-initializearray-and-finalizearray }
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
