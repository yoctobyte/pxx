program ds_field_md2;
type TA = array[0..1, 0..1] of Double; TP = ^TA; TPP = ^TP; TR = record q: TP; end;
var
  a: TA;
  r: TR;
  i: Integer;
begin
  r.q := @a;
  for i := 0 to 3 do r.q^[i div 2, i mod 2] := (i+1)*1.5;
  Write(a[0,0]:0:2, ' ', a[1,1]:0:2);
  Write(' | ');
  WriteLn(r.q^[0,0]:0:2, ' ', r.q^[1,1]:0:2);
end.
