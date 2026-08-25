program map_int;
{ fgl rung: TFPGMap<Integer,Integer> — Add / KeyData / sorted key order. }
uses fgl;
type
  TIntMap = specialize TFPGMap<Integer, Integer>;
var
  m: TIntMap;
  i: Integer;
begin
  m := TIntMap.Create;
  m.Add(5, 50);
  m.Add(2, 20);
  m.Add(9, 90);
  writeln('count=', m.Count);
  writeln('m[5]=', m.KeyData[5], ' m[2]=', m.KeyData[2], ' m[9]=', m.KeyData[9]);
  write('keys:');
  for i := 0 to m.Count - 1 do write(' ', m.Keys[i], '=', m.Data[i]);
  writeln;
  writeln('indexof(9)=', m.IndexOf(9));
  m.Free;
end.
