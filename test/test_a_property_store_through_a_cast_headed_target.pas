{ A PROPERTY STORE WHOSE TARGET IS HEADED BY A TYPE CAST.

  All three spellings were REFUSED — `expected ':=' before ';'` — while the
  identical stores through a plain variable (`pc^...`) worked and fpc 3.2.2
  accepts all six:

      PTC(raw)^.P := 21        plain property
      PTC(raw)^.A[2] := 22     indexed property
      PTC(raw)^[3] := 23       default property

  Cause, and it is the opposite of what the ticket predicted. The shared
  selector walker asks PropAccessIsWrite for itself; on a property target it
  emits the SETTER and consumes the `:=` AND the value with it. Both cast arms
  then ran Expect(tkAssign) on a token that was no longer there. So the merge
  hazard was never "the expression path might CALL something it should not" —
  it was that the expression path had already DONE the store and nobody told
  the caller.

  The convention is the one this file already used for the non-cast spellings:
  a call node in target position IS the statement. The extra conjunct is that
  the `:=` must be GONE, which is what separates a completed store from
  `PTC(raw)^.Func := 5` — still an error, and now the same error the other two
  spellings always gave rather than an IR_UNSUPPORTED internal message.

  EVERY CAST ROW IS PAIRED WITH THE SAME STORE THROUGH A VARIABLE. The variable
  rows were right on the pin too, so they say the defect is the OPENER and not
  the feature. Accessors print their own names because the values alone cannot
  tell a store that went through the setter from one that went somewhere else —
  row 5's `arr[3]` is written by both the right answer and a raw subscript.

  refactor-p-one-lvalue-path-for-statements-and-expressions }
program test_a_property_store_through_a_cast_headed_target;
type
  TC = class
    v: Integer;
    arr: array[0..3] of Integer;
    function GetV: Integer;
    procedure SetV(x: Integer);
    function GetA(i: Integer): Integer;
    procedure SetA(i, x: Integer);
    procedure Bump;
    property P: Integer read GetV write SetV;
    property A[i: Integer]: Integer read GetA write SetA; default;
  end;
  PTC = ^TC;
var o: TC; pc: PTC; raw: Pointer;
function TC.GetV: Integer; begin WriteLn('  [GetV]'); Result := v; end;
procedure TC.SetV(x: Integer); begin WriteLn('  [SetV]'); v := x; end;
function TC.GetA(i: Integer): Integer; begin WriteLn('  [GetA]'); Result := arr[i]; end;
procedure TC.SetA(i, x: Integer); begin WriteLn('  [SetA]'); arr[i] := x; end;
procedure TC.Bump; begin WriteLn('  [Bump]'); v := v + 1; end;
begin
  o := TC.Create; pc := @o; raw := pc;
  WriteLn('1 var  .P :=');     pc^.P := 1;         WriteLn('  v=', o.v);
  WriteLn('2 cast .P :=');     PTC(raw)^.P := 21;  WriteLn('  v=', o.v);
  WriteLn('3 var  .A[] :=');   pc^.A[2] := 2;      WriteLn('  arr2=', o.arr[2]);
  WriteLn('4 cast .A[] :=');   PTC(raw)^.A[2] := 22; WriteLn('  arr2=', o.arr[2]);
  WriteLn('5 var  [] :=');     pc^[3] := 3;        WriteLn('  arr3=', o.arr[3]);
  WriteLn('6 cast [] :=');     PTC(raw)^[3] := 23; WriteLn('  arr3=', o.arr[3]);
  WriteLn('7 var  proc');      pc^.Bump;           WriteLn('  v=', o.v);
  WriteLn('8 cast proc');      PTC(raw)^.Bump;     WriteLn('  v=', o.v);
end.
