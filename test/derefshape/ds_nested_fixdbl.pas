program ds_nested_fixdbl;
type TA = array[0..3] of Double; TP = ^TA; TPP = ^TP; TR = record q: TP; end;
var
  a: TA;
  p: TP;
  pp: TPP;
  i: Integer;
begin
  p := @a;
  pp := @p;
  for i := 0 to 3 do pp^^[i] := (i+1)*1.5;
  Write(a[0]:0:2, ' ', a[3]:0:2);
  Write(' | ');
  WriteLn(pp^^[0]:0:2, ' ', pp^^[3]:0:2);
end.
