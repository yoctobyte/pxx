program ds_nested_dyndbl;
type TA = array of Double; TP = ^TA; TPP = ^TP; TR = record q: TP; end;
var
  a: TA;
  p: TP;
  pp: TPP;
  i: Integer;
begin
  SetLength(a, 4);
  p := @a;
  pp := @p;
  for i := 0 to 3 do pp^^[i] := (i+1)*1.5;
  WriteLn(a[0]:0:2, ' ', a[3]:0:2);
end.
