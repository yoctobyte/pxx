program ds_plain_fixdbl;
type TA = array[0..3] of Double; TP = ^TA; TR = record q: TP; end;
var
  a: TA;
  p: TP;
  i: Integer;
begin
  p := @a;
  for i := 0 to 3 do p^[i] := (i+1)*1.5;
  WriteLn(a[0]:0:2, ' ', a[3]:0:2);
end.
