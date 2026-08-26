program map_str;
{ fgl rung: TFPGMap<string,Integer> — string-keyed map. }
uses fgl;
type
  TStrMap = specialize TFPGMap<string, Integer>;
var
  m: TStrMap;
  i: Integer;
begin
  m := TStrMap.Create;
  m.Add('bee', 2);
  m.Add('ant', 1);
  m.Add('cow', 3);
  writeln('count=', m.Count);
  writeln('m[cow]=', m.KeyData['cow']);
  write('keys:');
  for i := 0 to m.Count - 1 do write(' ', m.Keys[i], '=', m.Data[i]);
  writeln;
  m.Free;
end.
