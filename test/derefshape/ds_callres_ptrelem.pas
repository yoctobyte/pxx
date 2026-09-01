program ds_callres_ptrelem;
type TA = array of PInteger; TP = ^TA; TR = record q: TP; end;
var
  a: TA;
  nums: array[0..3] of Integer;
  i: Integer;
function GetP: TP; begin GetP := @a; end;
begin
  for i := 0 to 3 do nums[i] := 10 + i;
  SetLength(a, 4);
  for i := 0 to 3 do GetP^[i] := @nums[i];
  WriteLn(a[0]^, ' ', a[3]^);
end.
