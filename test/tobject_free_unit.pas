unit tobject_free_unit;
{ A UNIT that frees through TObject: its Free must dispatch the override.
  bug-a-free-on-a-tobject-in-a-unit-skips-the-overridden-destructor }
{$mode objfpc}
interface
procedure FreeObj(p: Pointer);
procedure FreeTObj(o: TObject);
implementation
procedure FreeObj(p: Pointer);
begin
  TObject(p).Free;
end;
procedure FreeTObj(o: TObject);
begin
  o.Free;
end;
end.
