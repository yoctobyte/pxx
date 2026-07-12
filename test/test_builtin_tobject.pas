program test_builtin_tobject;
{ TObject as an instantiable class: var o: TObject; o := TObject.Create.
  The builtin root row (RegisterBuiltinTObject) + fieldless auto-Create +
  the obj.Free desugar. feature-pascal-builtin-tobject-class. }
type
  TC = class(TObject)
    x: Integer;
  end;
var
  o: TObject;
  c: TC;
begin
  o := TObject.Create;
  writeln(o = nil);       { FALSE — allocated }
  o.Free;
  c := TC.Create;
  c.x := 42;
  writeln(c.x);
  o := c;                 { child assignable to a TObject ref }
  writeln(o = nil);
  c.Free;
end.
