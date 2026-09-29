program test_an_owning_object_list_counts_its_destructors;
{ The destructor COUNT through TFPObjectList(OwnsObjects) Delete/Clear/Free;
  expected output is fpc 3.2.2's.
  bug-a-free-on-a-tobject-in-a-unit-skips-the-overridden-destructor }
{$mode objfpc}
uses contnrs;
var
  Destroyed: Integer = 0;
type
  TItem = class
    destructor Destroy; override;
  end;
destructor TItem.Destroy;
begin
  Inc(Destroyed);
  inherited Destroy;
end;
var
  L: TFPObjectList;
  i: Integer;
begin
  L := TFPObjectList.Create(True);
  for i := 1 to 5 do L.Add(TItem.Create);
  L.Delete(0);
  writeln('after Delete: ', Destroyed);
  L.Clear;
  writeln('after Clear: ', Destroyed);
  for i := 1 to 3 do L.Add(TItem.Create);
  L.Free;
  writeln('after Free: ', Destroyed);
end.
