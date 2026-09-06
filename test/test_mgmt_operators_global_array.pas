program test_mgmt_operators_global_array;
{ A GLOBAL array of a record with management operators. Globals are wrapped by
  WrapMainBodyManagementOps — a separate call into the same pass — and one arm
  being right has never implied the other here, which is why this pair exists at
  all.

  IT WAS A REFUSAL FIXTURE AND IT EXPIRED WHEN THE LOOP LANDED. Its old header
  is worth keeping, because it records why a refusal test can be green for a
  reason that has nothing to do with the guard: the check read the symbol's
  RecName, which only AllocVar/AllocParam ever write — for an array the record
  id lives in ElemRecName — and it passed only because symbol slots are
  RECYCLED and the stale value happened to be the right record. When 4a3c88532
  cleared that field on recycle, both arms went silent at once and an array of a
  managed record compiled with an Initialize that never runs.
  regression-test-core-test-mgmt-operators

  TWO DIVERGENCES FROM FPC 3.2.2, BOTH MEASURED, BOTH IN THE SAME DIRECTION —
  fpc runs FEWER operators here than we do, and this .expected is therefore ours
  rather than fpc's:

   1. fpc runs NOTHING for a global array. Measured: this program under fpc
      3.2.2 prints `body 000` and no init or fin line at all — while for a plain
      global RECORD it does run Initialize. So the omission is about the array,
      not about globals, and it leaves a declared invariant that never runs,
      which is the exact defect this feature exists to remove. We initialize.
   2. fpc never finalizes a record-typed global either. That is already the
      chosen position for the non-array case (divergence 1 in
      test_mgmt_operators's header): a Finalize that never runs is a leak by
      construction, and Delphi finalizes too. The array case inherits it.

  The ORDER claims are not ours to choose and are not diverged: elements
  ascending in both directions, which is fpc's measured rule for locals and is
  covered byte-for-byte against fpc in test_mgmt_operators_array.

  feature-pascal-management-operators-nested-and-array }
{$mode objfpc}{$H+}{$modeswitch advancedrecords}
type
  TFoo = record
    n: Integer;
    class operator Initialize(var a: TFoo);
    class operator Finalize(var a: TFoo);
  end;

var
  seq: Integer;
  arr: array[2..4] of TFoo;

class operator TFoo.Initialize(var a: TFoo);
begin
  a.n := seq;
  writeln('init ', seq);
  seq := seq + 1;
end;

class operator TFoo.Finalize(var a: TFoo);
begin
  writeln('fin ', a.n);
end;

begin
  writeln('body ', arr[2].n, arr[3].n, arr[4].n);
end.
