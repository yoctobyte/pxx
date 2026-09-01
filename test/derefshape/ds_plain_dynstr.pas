program ds_plain_dynstr;
type TA = array of AnsiString; TP = ^TA; TPP = ^TP; TR = record q: TP; end;
var
  a: TA;
  p: TP;
  i: Integer;
begin
  SetLength(a, 4);
  p := @a;
  for i := 0 to 3 do p^[i] := 'v' + Chr(48+i);
  Write(a[0], ' ', a[3]);
  Write(' | ');
  WriteLn(p^[0], ' ', p^[3]);
end.
