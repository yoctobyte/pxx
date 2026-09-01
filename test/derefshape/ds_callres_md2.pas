program ds_callres_md2;
type TA = array[0..1, 0..1] of Double; TP = ^TA; TPP = ^TP; TR = record q: TP; end;
var
  a: TA;
  i: Integer;
function GetP: TP; begin GetP := @a; end;
begin
  for i := 0 to 3 do GetP^[i div 2, i mod 2] := (i+1)*1.5;
  WriteLn(a[0,0]:0:2, ' ', a[1,1]:0:2);
end.
