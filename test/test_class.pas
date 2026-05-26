program test_class;
type
  TMyClass = class
    x: Integer;
    y: Integer;
  end;
var
  obj1, obj2: TMyClass;
begin
  obj1 := TMyClass.Create;
  obj2 := TMyClass.Create;
  
  if obj1 <> 0 then writeln(1) else writeln(0);
  if obj2 <> 0 then writeln(1) else writeln(0);
  if obj2 <> obj1 then writeln(1) else writeln(0);
  
  obj1.x := 42;
  obj1.y := 100;
  
  obj2.x := 999;
  obj2.y := 888;
  
  writeln(obj1.x);
  writeln(obj1.y);
  writeln(obj2.x);
  writeln(obj2.y);
end.
