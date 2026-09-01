program ds_plain_md2;
type TA = array[0..1, 0..1] of Double; TP = ^TA; TPP = ^TP; TR = record q: TP; end;
var
  a: TA;
  p: TP;
  i: Integer;
begin
  p := @a;
  for i := 0 to 3 do p^[i div 2, i mod 2] := (i+1)*1.5;
  WriteLn(a[0,0]:0:2, ' ', a[1,1]:0:2);
end.
