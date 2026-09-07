program test_mgmt_operators_multidim_array_field_refused;
{ The OTHER array-field shape the synthesised loop cannot reach, and it is not
  the same reason as the dynamic one in test_mgmt_operators_field_refused: a
  multi-dimensional field has a perfectly readable extent and the loop is 1-D.

  THE LOW BOUNDS HERE ARE NOT DECORATION AND A 0-BASED VERSION OF THIS FILE IS
  A GUARD THAT CANNOT FAIL. Measured 2026-09-07 by removing the NDims test from
  FldIsLoopableManagedArray and rebuilding: for `array[0..1, 0..2] of TFoo` the
  flat loop is CORRECT and matches fpc 3.2.2 element for element, because
  UFldArrLen is the FLAT count (6) and the field's own low bound is 0, so
  running 0..5 addresses exactly the six elements. The bug only appears once the
  OUTER dimension starts anywhere but zero: with `array[1..2, 5..7]` the same
  poisoned compiler printed `body 001234` against fpc's `012345` and finalized a
  sixth element holding `9`, which is the neighbouring `k` field -- a silent
  write outside the array and one element never initialized at all.

  So this fixture uses 1..2 and 5..7. If someone deletes the NDims test, a
  0-based fixture goes on passing and certifies the removal; this one does not.
  feature-pascal-management-operators-nested-and-array }
{$mode objfpc}{$H+}{$modeswitch advancedrecords}
type
  TFoo = record
    n: Integer;
    class operator Initialize(var a: TFoo);
  end;
  TBar = record
    f: array[1..2, 5..7] of TFoo;
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
