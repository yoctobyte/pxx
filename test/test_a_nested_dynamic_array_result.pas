program test_a_nested_dynamic_array_result;
{ `function F: array of array of T` — the Result slot at its DECLARED nesting.

  Result was allocated with `AllocDynArray('Result', retElemTk, 1)`, a hardcoded
  depth, while the proc row (ProcRetDynDepth) already carried the real one. So
  for a nested result an OUTER element was read as a 4-byte Integer instead of
  an 8-byte handle: inside the function `Length(Result[1])` answered garbage
  (855638216) and `Result[1] := row` stored a truncated handle, which the caller
  then indexed into a SEGFAULT. `SetLength(Result[0], 2)` — sizing an inner row
  through Result — was refused outright for the same reason.

  Everything else about the value was already right, which is what made it a
  narrow symbol-shape bug rather than an ABI one: a nested dyn-array LOCAL
  worked, `Result := loc` transferred correctly, and a `var` parameter of the
  same type worked. Only Result's own shape was wrong.

  Two more halves fell out of it and are asserted here too:
  - `Length(MakeMat[1])` went through the value path and derefed the handle,
    printing 0x600000007 (the row's first two elements as one 8-byte word). The
    IR arm that lifts a dyn-array call result for Length keyed on ONE spelling
    (`AN_CALL` with ProcRetIsDynArray) instead of on the value's shape.
  - `for i in MakeMat[1]` said "undefined variable (MakeMat)": the for-in
    qualified-source dispatch looked the name up with FindSym only.

  .expected IS fpc 3.2.2's own output on this source. }
{$mode objfpc}{$H+}

uses SysUtils;

var
  calleeSeen: string;

type
  TRow  = array of Integer;
  TMat  = array of TRow;
  TMat2 = array of array of Integer;   { the un-aliased inner spelling }
  TCube = array of array of array of Integer;
  TSRow = array of string;
  TSMat = array of TSRow;

{ rows built as locals and assigned in — the shape that SEGFAULTED }
function MakeByAssign: TMat;
var r0, r1: TRow;
begin
  SetLength(r0, 2); r0[0] := 1; r0[1] := 2;
  SetLength(r1, 3); r1[0] := 3; r1[1] := 4; r1[2] := 5;
  SetLength(Result, 2); Result[0] := r0; Result[1] := r1;
  { read back through Result, inside the callee — this answered garbage. Banked
    in a global rather than written here: the function is called from inside
    several WriteLn argument lists below, and a Write of its own would interleave
    with theirs and assert argument-evaluation order instead of this bug. }
  calleeSeen := IntToStr(Length(Result)) + ' ' + IntToStr(Length(Result[1])) +
                ' ' + IntToStr(Result[1][2]);
end;

{ rows sized THROUGH Result — this was refused with "SetLength expects an array
  variable in IR codegen" }
function MakeBySetLen: TMat2;
begin
  SetLength(Result, 2);
  SetLength(Result[0], 1); Result[0][0] := 9;
  SetLength(Result[1], 2); Result[1][0] := 8; Result[1][1] := 7;
end;

function MakeCube: TCube;
begin
  SetLength(Result, 2);
  SetLength(Result[0], 1); SetLength(Result[0][0], 2);
  Result[0][0][0] := 1; Result[0][0][1] := 2;
  SetLength(Result[1], 1); SetLength(Result[1][0], 2);
  Result[1][0][0] := 3; Result[1][0][1] := 4;
end;

{ a MANAGED element at the base: the inner handle must survive the copy out }
function MakeStrs: TSMat;
begin
  SetLength(Result, 2);
  SetLength(Result[0], 2); Result[0][0] := 'alpha'; Result[0][1] := 'beta';
  SetLength(Result[1], 1); Result[1][0] := 'gamma';
end;

var
  m: TMat; row: TRow; i, j, s: Integer;
begin
  m := MakeByAssign;
  WriteLn('callee : ', calleeSeen);
  WriteLn('var    : ', Length(m), ' ', Length(m[1]), ' ', m[1][2]);
  { the same value indexed straight off the call }
  WriteLn('call   : ', Length(MakeByAssign), ' ', Length(MakeByAssign[1]));
  WriteLn('callel : ', MakeByAssign[1][2]);
  WriteLn('setlen : ', Length(MakeBySetLen), ' ', Length(MakeBySetLen[1]), ' ', MakeBySetLen[1][1]);
  WriteLn('cube   : ', Length(MakeCube), ' ', Length(MakeCube[1]), ' ',
                       Length(MakeCube[1][0]), ' ', MakeCube[1][0][1]);
  WriteLn('strs   : ', Length(MakeStrs), ' ', Length(MakeStrs[0]), ' ', MakeStrs[0][1]);
  { High over each level }
  WriteLn('high   : ', High(MakeByAssign), ' ', High(MakeByAssign[1]));
  { for-in over a row of a call result, and over the matrix itself }
  s := 0;
  for i in MakeByAssign[1] do s := s + i;
  WriteLn('forinrow : ', s);
  s := 0;
  for row in MakeByAssign do for j in row do s := s + j;
  WriteLn('forinmat : ', s);
  { and the same two through a variable, which always worked }
  s := 0;
  for row in m do for j in row do s := s + j;
  WriteLn('forinvar : ', s);
end.
