program ds_arrayelem_md2;
type TA = array[0..1, 0..1] of Double; TP = ^TA; TPP = ^TP; TR = record q: TP; end;
var
  a: TA;
  ap: array[0..1] of TP;
  i: Integer;
begin
  ap[0] := @a;
  for i := 0 to 3 do ap[0]^[i div 2, i mod 2] := (i+1)*1.5;
  WriteLn(a[0,0]:0:2, ' ', a[1,1]:0:2);
end.
