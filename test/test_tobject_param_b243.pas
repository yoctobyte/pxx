program test_tobject_param_b243;
{ TObject-typed params must carry the FULL pointer (they fell to tyInteger =
  32-bit truncation) and match any class instance in plain routines too
  (bug-tobject-param-truncated-32bit). }
type
  TObj = class
    x: Integer;
    procedure H(Sender: TObject);
  end;
var target: TObj;
procedure TObj.H(Sender: TObject);
begin
  writeln('m-ident=', Pointer(Sender) = Pointer(target));
  if TObj(Sender) = target then
    writeln('m-cast=', TObj(Sender).x);
end;
procedure P(o: TObject);
begin
  writeln('p-ident=', Pointer(o) = Pointer(target));
  writeln('p-cast=', TObj(o).x);
end;
begin
  target := TObj.Create;
  target.x := 77;
  target.H(target);
  P(target);
end.
