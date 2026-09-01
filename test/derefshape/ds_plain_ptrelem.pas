program ds_plain_ptrelem;
type TA = array of PInteger; TP = ^TA; TPP = ^TP; TR = record q: TP; end;
var
  a: TA;
  nums: array[0..3] of Integer;
  p: TP;
  i: Integer;
begin
  for i := 0 to 3 do nums[i] := 10 + i;
  SetLength(a, 4);
  p := @a;
  for i := 0 to 3 do p^[i] := @nums[i];
  Write(a[0]^, ' ', a[3]^);
  Write(' | ');
  WriteLn(p^[0]^, ' ', p^[3]^);
end.
