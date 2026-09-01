program ds_cast_fixdbl;
type TA = array[0..3] of Double; TP = ^TA; TR = record q: TP; end;
var
  a: TA;
  raw: Pointer;
  i: Integer;
begin
  raw := @a;
  for i := 0 to 3 do TP(raw)^[i] := (i+1)*1.5;
  WriteLn(a[0]:0:2, ' ', a[3]:0:2);
end.
