program ds_field_dynstr;
type TA = array of AnsiString; TP = ^TA; TR = record q: TP; end;
var
  a: TA;
  r: TR;
  i: Integer;
begin
  SetLength(a, 4);
  r.q := @a;
  for i := 0 to 3 do r.q^[i] := 'v' + Chr(48+i);
  WriteLn(a[0], ' ', a[3]);
end.
