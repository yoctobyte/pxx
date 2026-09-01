program ds_cast_dynstr;
type TA = array of AnsiString; TP = ^TA; TPP = ^TP; TR = record q: TP; end;
var
  a: TA;
  raw: Pointer;
  i: Integer;
begin
  SetLength(a, 4);
  raw := @a;
  for i := 0 to 3 do TP(raw)^[i] := 'v' + Chr(48+i);
  Write(a[0], ' ', a[3]);
  Write(' | ');
  WriteLn(TP(raw)^[0], ' ', TP(raw)^[3]);
end.
