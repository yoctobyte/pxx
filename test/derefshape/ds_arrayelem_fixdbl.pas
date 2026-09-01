program ds_arrayelem_fixdbl;
type TA = array[0..3] of Double; TP = ^TA; TPP = ^TP; TR = record q: TP; end;
var
  a: TA;
  ap: array[0..1] of TP;
  i: Integer;
begin
  ap[0] := @a;
  for i := 0 to 3 do ap[0]^[i] := (i+1)*1.5;
  WriteLn(a[0]:0:2, ' ', a[3]:0:2);
end.
