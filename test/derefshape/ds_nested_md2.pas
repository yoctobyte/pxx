program ds_nested_md2;
type TA = array[0..1, 0..1] of Double; TP = ^TA; TPP = ^TP; TR = record q: TP; end;
var
  a: TA;
  p: TP;
  pp: TPP;
  i: Integer;
begin
  p := @a;
  pp := @p;
  for i := 0 to 3 do pp^^[i div 2, i mod 2] := (i+1)*1.5;
  Write(a[0,0]:0:2, ' ', a[1,1]:0:2);
  Write(' | ');
  WriteLn(pp^^[0,0]:0:2, ' ', pp^^[1,1]:0:2);
end.
