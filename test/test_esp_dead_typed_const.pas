program test_esp_dead_typed_const;
{ DEAD TYPED CONSTS GO TO FLASH, LIVE ONES STAY WRITABLE (2026-10-13). On an
  ESP object a baked typed const that no surviving routine references moves
  to .rodata (ObjRoAdoptDeadTypedConsts). Dead is decided after DCE, so the
  live tables here must still be writable -- {$J+} assignment, an element
  passed as a var parameter, Inc on an element -- while Unused (read only by
  NeverCalled, which nothing calls) sits in flash. A wrong verdict on a live
  table shows as a store fault; a wrong address as a wrong line. Compared
  with the x86-64 oracle. }
const
  Counts: array[0..4] of Integer = (1, 2, 3, 4, 5);
  Scale: array[0..2] of Int64 = (10, 100, 1000);
  Unused: array[0..63] of Int64 = (
    1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11, 12, 13, 14, 15, 16,
    17, 18, 19, 20, 21, 22, 23, 24, 25, 26, 27, 28, 29, 30, 31, 32,
    33, 34, 35, 36, 37, 38, 39, 40, 41, 42, 43, 44, 45, 46, 47, 48,
    49, 50, 51, 52, 53, 54, 55, 56, 57, 58, 59, 60, 61, 62, 63, 64);
var i: Integer; t: Int64;

function NeverCalled(k: Integer): Int64;
begin
  Result := Unused[k];
end;

procedure Bump(var x: Integer);
begin
  x := x * 7;
end;

begin
  Counts[2] := 30;
  Bump(Counts[4]);
  Inc(Counts[0], 100);
  Scale[1] := Scale[1] + 5;
  t := 0;
  for i := 0 to 4 do t := t + Counts[i];
  WriteLn('counts ', Counts[0], ' ', Counts[2], ' ', Counts[4], ' sum ', t);
  WriteLn('scale ', Scale[0], ' ', Scale[1], ' ', Scale[2]);
  WriteLn('done');
end.
