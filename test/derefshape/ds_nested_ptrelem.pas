program ds_nested_ptrelem;
type TA = array of PInteger; TP = ^TA; TPP = ^TP; TR = record q: TP; end;
var
  a: TA;
  nums: array[0..3] of Integer;
  p: TP;
  pp: TPP;
  i: Integer;
begin
  for i := 0 to 3 do nums[i] := 10 + i;
  SetLength(a, 4);
  p := @a;
  pp := @p;
  for i := 0 to 3 do pp^^[i] := @nums[i];
  WriteLn(a[0]^, ' ', a[3]^);
end.
