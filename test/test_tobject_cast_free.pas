program test_tobject_cast_free;
type TObj = class x: Integer; end;
var o: TObj;
begin
  o := TObj.Create; o.x := 5;
  TObject(o).Free;
  writeln('ok');
end.
