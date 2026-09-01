program ds_arrayelem_dynstr;
type TA = array of AnsiString; TP = ^TA; TR = record q: TP; end;
var
  a: TA;
  ap: array[0..1] of TP;
  i: Integer;
begin
  SetLength(a, 4);
  ap[0] := @a;
  for i := 0 to 3 do ap[0]^[i] := 'v' + Chr(48+i);
  WriteLn(a[0], ' ', a[3]);
end.
