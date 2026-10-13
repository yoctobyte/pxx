program esp_obj_dead_typed_const;
{ A typed const array that DCE leaves unreferenced goes to .rodata (flash) in
  an ESP object; one a live routine reads stays in .data. TableB is read only
  by UseB, which is called only under -dUSE_B, so the test-emit-obj row
  compares .data with and without the define: it must be at least TableB's
  800 bytes larger when UseB is live. See ObjRoAdoptDeadTypedConsts. }
const
  TableA: array[0..3] of Integer = (11, 22, 33, 44);
  TableB: array[0..99] of Int64 = (
    1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11, 12, 13, 14, 15, 16, 17, 18, 19, 20,
    21, 22, 23, 24, 25, 26, 27, 28, 29, 30, 31, 32, 33, 34, 35, 36, 37, 38, 39, 40,
    41, 42, 43, 44, 45, 46, 47, 48, 49, 50, 51, 52, 53, 54, 55, 56, 57, 58, 59, 60,
    61, 62, 63, 64, 65, 66, 67, 68, 69, 70, 71, 72, 73, 74, 75, 76, 77, 78, 79, 80,
    81, 82, 83, 84, 85, 86, 87, 88, 89, 90, 91, 92, 93, 94, 95, 96, 97, 98, 99, 100);
var i: Integer;

function UseB(k: Integer): Int64;
begin
  Result := TableB[k];
end;

begin
  i := 2;
  WriteLn(TableA[i]);
{$ifdef USE_B}
  WriteLn(UseB(i));
{$endif}
end.
