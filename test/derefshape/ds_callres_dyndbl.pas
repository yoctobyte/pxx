program ds_callres_dyndbl;
type TA = array of Double; TP = ^TA; TPP = ^TP; TR = record q: TP; end;
var
  a: TA;
  i: Integer;
function GetP: TP; begin GetP := @a; end;
begin
  SetLength(a, 4);
  for i := 0 to 3 do GetP^[i] := (i+1)*1.5;
  WriteLn(a[0]:0:2, ' ', a[3]:0:2);
end.
