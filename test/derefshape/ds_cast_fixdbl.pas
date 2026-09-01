program ds_cast_fixdbl;
type TA = array[0..3] of Double; TP = ^TA; TPP = ^TP; TR = record q: TP; end;
var
  a: TA;
  raw: Pointer;
  i: Integer;
begin
  raw := @a;
  for i := 0 to 3 do TP(raw)^[i] := (i+1)*1.5;
  Write(a[0]:0:2, ' ', a[3]:0:2);
  Write(' | ');
  WriteLn(TP(raw)^[0]:0:2, ' ', TP(raw)^[3]:0:2);
end.
