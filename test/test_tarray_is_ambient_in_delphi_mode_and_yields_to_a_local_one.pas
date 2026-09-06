program test_tarray_is_ambient_in_delphi_mode_and_yields_to_a_local_one;
{ The Delphi spelling of the same ambient type -- `TArray<T>` with no
  `specialize` and no `uses` -- plus the control that matters more than the
  feature: a program declaring its OWN TArray still wins, because the injection
  is parsed before the program's declarations and is shadowed by them. }
{$mode delphi}
type
  TRec = record A: TArray<Byte>; B: Integer; end;
var
  r: TArray<LongInt>;
  q: TRec;
begin
  SetLength(r, 3); r[1] := 8;
  WriteLn('1 ', Length(r), ' ', r[1]);
  SetLength(q.A, 2); q.A[0] := 4; q.B := 5;
  WriteLn('2 ', Length(q.A), ' ', q.A[0], ' ', q.B);
end.
