program ds_field_ptrelem;
type TA = array of PInteger; TP = ^TA; TR = record q: TP; end;
var
  a: TA;
  nums: array[0..3] of Integer;
  r: TR;
  i: Integer;
begin
  for i := 0 to 3 do nums[i] := 10 + i;
  SetLength(a, 4);
  r.q := @a;
  for i := 0 to 3 do r.q^[i] := @nums[i];
  WriteLn(a[0]^, ' ', a[3]^);
end.
