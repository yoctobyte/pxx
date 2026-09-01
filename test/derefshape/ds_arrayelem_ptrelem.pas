program ds_arrayelem_ptrelem;
type TA = array of PInteger; TP = ^TA; TPP = ^TP; TR = record q: TP; end;
var
  a: TA;
  nums: array[0..3] of Integer;
  ap: array[0..1] of TP;
  i: Integer;
begin
  for i := 0 to 3 do nums[i] := 10 + i;
  SetLength(a, 4);
  ap[0] := @a;
  for i := 0 to 3 do ap[0]^[i] := @nums[i];
  WriteLn(a[0]^, ' ', a[3]^);
end.
