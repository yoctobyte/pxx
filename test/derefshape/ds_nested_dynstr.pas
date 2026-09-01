program ds_nested_dynstr;
type TA = array of AnsiString; TP = ^TA; TPP = ^TP; TR = record q: TP; end;
var
  a: TA;
  p: TP;
  pp: TPP;
  i: Integer;
begin
  SetLength(a, 4);
  p := @a;
  pp := @p;
  for i := 0 to 3 do pp^^[i] := 'v' + Chr(48+i);
  WriteLn(a[0], ' ', a[3]);
end.
