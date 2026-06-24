program lib_classes;
{ Smoke for the classic Classes (TList / TStrings / TStringList) — exercises the
  indexed/default properties and the abstract-base polymorphism end to end. }
uses classes;

procedure SayBool(const tag: string; b: Boolean);
begin
  if b then writeln(tag, '=ok') else writeln(tag, '=FAIL');
end;

var
  list: TList;
  sl: TStringList;
  ss: TStrings;          { declare as base, instantiate concrete }
  marker: TObject;
begin
  { ---- TList: default [i] property, Add, Insert, Delete, IndexOf, Remove ---- }
  list := TList.Create;
  list.Add(Pointer(10));
  list.Add(Pointer(20));
  list.Add(Pointer(30));
  SayBool('list-count', list.Count = 3);
  SayBool('list-default', Int64(list[1]) = 20);          { default property }
  SayBool('list-items', Int64(list.Items[2]) = 30);      { named property }
  list[0] := Pointer(99);
  SayBool('list-write', Int64(list[0]) = 99);
  SayBool('list-indexof', list.IndexOf(Pointer(30)) = 2);
  list.Insert(1, Pointer(15));
  SayBool('list-insert', (Int64(list[1]) = 15) and (list.Count = 4));
  list.Delete(1);
  SayBool('list-delete', (Int64(list[1]) = 20) and (list.Count = 3));
  list.Remove(Pointer(99));
  SayBool('list-remove', (Int64(list[0]) = 20) and (list.Count = 2));
  list.Free;

  { ---- TStringList: Strings[]/default [i], Objects[], Sort, Text ---- }
  sl := TStringList.Create;
  sl.Add('banana');
  sl.Add('apple');
  sl.Add('cherry');
  SayBool('sl-count', sl.Count = 3);
  SayBool('sl-default', sl[1] = 'apple');                 { default property }
  SayBool('sl-strings', sl.Strings[0] = 'banana');
  SayBool('sl-indexof', sl.IndexOf('cherry') = 2);

  marker := TList.Create;        { any TObject descendant serves as the marker }
  sl.Objects[1] := marker;
  SayBool('sl-object', sl.Objects[1] = marker);

  { Text in insertion order. NOTE: sl.Sort is correct but blocked by
    bug-string-ordering-comparison-constant (string < / > are stuck) — re-add a
    sorted check when that Track A bug is fixed. }
  SayBool('sl-text', sl.Text = 'banana'#13#10'apple'#13#10'cherry'#13#10);
  sl.Free;

  { ---- TStrings base reference to a TStringList (the standard idiom) ---- }
  ss := TStringList.Create;
  ss.Add('x');
  ss.Add('y');
  SayBool('strings-base', (ss.Count = 2) and (ss[1] = 'y'));
  ss.SetText('one'#10'two'#10'three');
  SayBool('strings-settext', (ss.Count = 3) and (ss[2] = 'three'));
  ss.Free;
end.
