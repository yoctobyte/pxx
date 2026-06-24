program lib_classes;
{ Smoke for the classic Classes. TList is exercised end to end (indexed/default
  properties, Add/Insert/Delete/IndexOf/Remove). TStrings/TStringList are written
  but blocked by bug-mixed-signature-vmt-misdispatch (Track A) — re-enable their
  checks once that VMT bug is fixed. }
uses classes;

procedure SayBool(const tag: string; b: Boolean);
begin
  if b then writeln(tag, '=ok') else writeln(tag, '=FAIL');
end;

var
  list: TList;
begin
  { TList: default [i] property, Add, Insert, Delete, IndexOf, Remove. }
  list := TList.Create;
  list.Add(Pointer(10));
  list.Add(Pointer(20));
  list.Add(Pointer(30));
  SayBool('count', list.Count = 3);
  SayBool('default-idx', Int64(list[1]) = 20);          { default property }
  SayBool('items', Int64(list.Items[2]) = 30);          { named property }
  list[0] := Pointer(99);                                { default write }
  SayBool('write', Int64(list[0]) = 99);
  SayBool('indexof', list.IndexOf(Pointer(30)) = 2);
  list.Insert(1, Pointer(15));
  SayBool('insert', (Int64(list[1]) = 15) and (list.Count = 4));
  list.Delete(1);
  SayBool('delete', (Int64(list[1]) = 20) and (list.Count = 3));
  list.Remove(Pointer(99));
  SayBool('remove', (Int64(list[0]) = 20) and (list.Count = 2));
  list.Free;
end.
