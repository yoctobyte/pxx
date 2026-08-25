program list_int;
{ fgl rung: TFPGList<Integer> — Add/IndexOf/Insert/Delete/Sort/for-in. }
uses fgl;
type
  TIntList = specialize TFPGList<Integer>;

function CmpInt(const a, b: Integer): Integer;
begin
  if a < b then CmpInt := -1
  else if a > b then CmpInt := 1
  else CmpInt := 0;
end;

var
  l: TIntList;
  i, v: Integer;
begin
  l := TIntList.Create;
  l.Add(30); l.Add(10); l.Add(20);
  writeln('count=', l.Count);
  writeln('indexof=', l.IndexOf(10));
  l.Insert(1, 99);
  writeln('after-ins ', l[0], ' ', l[1], ' ', l[2], ' ', l[3]);
  l.Delete(0);
  writeln('after-del count=', l.Count, ' head=', l[0]);
  l.Add(30);
  l.Sort(@CmpInt);
  write('sorted:');
  for i := 0 to l.Count - 1 do write(' ', l[i]);
  writeln;
  write('forin:');
  for v in l do write(' ', v);
  writeln;
  l.Free;
end.
