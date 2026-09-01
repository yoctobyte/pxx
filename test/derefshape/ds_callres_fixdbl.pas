program ds_callres_fixdbl;
type TA = array[0..3] of Double; TP = ^TA; TR = record q: TP; end;
var
  a: TA;
  i: Integer;
function GetP: TP; begin GetP := @a; end;
begin
  for i := 0 to 3 do GetP^[i] := (i+1)*1.5;
  WriteLn(a[0]:0:2, ' ', a[3]:0:2);
end.
