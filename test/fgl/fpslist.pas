program fpslist;
{ fgl rung: TFPSList — the non-generic byte-sized base list every TFPG* rides on. }
uses fgl;
var
  l: TFPSList;
  i, v: Integer;
begin
  l := TFPSList.Create(SizeOf(Integer));
  for i := 1 to 4 do
  begin
    v := i * 11;
    l.Add(@v);
  end;
  writeln('count=', l.Count, ' itemsize=', l.ItemSize);
  write('items:');
  for i := 0 to l.Count - 1 do write(' ', PInteger(l.Items[i])^);
  writeln;
  l.Delete(1);
  writeln('after-del count=', l.Count, ' [1]=', PInteger(l.Items[1])^);
  l.Free;
end.
