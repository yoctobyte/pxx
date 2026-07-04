program test_fgl_use;
{ Flagship FPC-compat gate: compiles REAL FPC 3.2.2 fgl.pp (--mimic-fpc, pxx
  RTL shadowing) and exercises TFPGList<Integer> (Add/IndexOf/Insert/Delete/
  Sort-with-callback/for-in enumerator) + TFPGMap<Integer,Integer>. Skipped
  by the Makefile when /usr/share/fpcsrc is absent. }
uses fgl;
type
  TIntList = specialize TFPGList<Integer>;
  TIntMap = specialize TFPGMap<Integer, Integer>;

function CmpInt(const a, b: Integer): Integer;
begin
  if a < b then CmpInt := -1
  else if a > b then CmpInt := 1
  else CmpInt := 0;
end;

var
  l: TIntList;
  m: TIntMap;
  i, v: Integer;
begin
  l := TIntList.Create;
  l.Add(30); l.Add(10); l.Add(20);
  writeln('indexof=', l.IndexOf(10));
  l.Insert(1, 99);
  writeln('after-ins ', l[0], ' ', l[1], ' ', l[2], ' ', l[3]);
  l.Sort(@CmpInt);
  write('sorted:');
  for i := 0 to l.Count - 1 do write(' ', l[i]);
  writeln;
  for v in l do write('[', v, ']');
  writeln;
  l.Free;

  m := TIntMap.Create;
  m.Add(5, 50);
  m.Add(2, 20);
  m.Add(9, 90);
  writeln('map count=', m.Count, ' m[5]=', m.KeyData[5], ' m[2]=', m.KeyData[2]);
  m.Free;
end.
