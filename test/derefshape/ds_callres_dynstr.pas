program ds_callres_dynstr;
type TA = array of AnsiString; TP = ^TA; TPP = ^TP; TR = record q: TP; end;
var
  a: TA;
  i: Integer;
function GetP: TP; begin GetP := @a; end;
begin
  SetLength(a, 4);
  for i := 0 to 3 do GetP^[i] := 'v' + Chr(48+i);
  Write(a[0], ' ', a[3]);
  Write(' | ');
  WriteLn(GetP^[0], ' ', GetP^[3]);
end.
