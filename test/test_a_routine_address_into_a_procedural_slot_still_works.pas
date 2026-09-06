program test_a_routine_address_into_a_procedural_slot_still_works;
{ POSITIVE HALF, and it is the whole risk of the refusal beside it. The check
  fires on "the source is a CALL whose result is not itself procedural", so what
  it can break is every legitimate way of filling a procedural slot -- and a
  refusal test alone passes just as happily when the rule has been widened until
  nothing can be assigned to a procvar at all.

  ROW C IS THE ONE THAT DISTINGUISHES THE RULE FROM THE NEXT-WIDER ONE I MIGHT
  HAVE WRITTEN. `f := MakeCb` is a CALL in source position and its result IS
  procedural (ProcRetProcSig), so it must be accepted; a rule spelled "a call
  cannot fill a procedural slot" passes every other row in this file and fails
  only this one.
  bug-p-a-bare-function-name-assigned-to-a-procedural-variable-segfaults-outside-delphi-mode }
type
  TF = function: Integer;
  TRec = record f: TF; end;

function G: Integer;
begin
  G := 7;
end;

function MakeCb: TF;
begin
  MakeCb := @G;
end;

procedure Use(h: TF);
begin
  WriteLn('H ', h());
end;

var
  f, f2: TF;
  r: TRec;
  a: array[0..1] of TF;
begin
  f := @G;      WriteLn('A ', f());        { the address, explicitly }
  f2 := f;      WriteLn('B ', f2());       { procvar to procvar }
  f := MakeCb;  WriteLn('C ', f());        { a call RETURNING a procedural value }
  r.f := @G;    WriteLn('D ', r.f());      { record field }
  a[0] := @G;   WriteLn('E ', a[0]());     { array element }
  f := nil;     WriteLn('F ', Ord(f = nil));
  WriteLn('G ', G);                        { the bare name as a CALL, which is what it is }
  Use(@G);
end.
