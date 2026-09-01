program ds_plain_fixdbl;
type TA = array[0..3] of Double; TP = ^TA; TPP = ^TP; TR = record q: TP; end;
var
  a: TA;
  p: TP;
  i: Integer;
begin
  p := @a;
  for i := 0 to 3 do p^[i] := (i+1)*1.5;
  Write(a[0]:0:2, ' ', a[3]:0:2);
  Write(' | ');
  WriteLn(p^[0]:0:2, ' ', p^[3]:0:2);
end.
