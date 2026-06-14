program test_array_of_const;

{ `array of const` (TVarRec open array). Exercises element-tag dispatch, the
  value union, and Length() over the constructed dyn-array of TVarRec. Compiles
  and runs identically under FPC 3.2.2 (system.TVarRec) and PXX
  (builtinheap.TVarRec). }

procedure dump(const items: array of const);
var
  i: Integer;
begin
  for i := 0 to Length(items) - 1 do
  begin
    if items[i].VType = vtInteger then
      writeln('int ', items[i].VInteger)
    else if items[i].VType = vtAnsiString then
      writeln('str ', PChar(items[i].VAnsiString))
    else
      writeln('other');
  end;
  writeln('count ', Length(items));
end;

begin
  dump([10, 20, 30]);
  dump(['hi', 7, 'world']);
end.
