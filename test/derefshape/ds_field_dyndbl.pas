program ds_field_dyndbl;
type TA = array of Double; TP = ^TA; TPP = ^TP; TR = record q: TP; end;
var
  a: TA;
  r: TR;
  i: Integer;
begin
  SetLength(a, 4);
  r.q := @a;
  for i := 0 to 3 do r.q^[i] := (i+1)*1.5;
  Write(a[0]:0:2, ' ', a[3]:0:2);
  Write(' | ');
  WriteLn(r.q^[0]:0:2, ' ', r.q^[3]:0:2);
end.
