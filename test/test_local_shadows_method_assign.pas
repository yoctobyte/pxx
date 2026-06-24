{ Regression: a local var whose name matches a method of the enclosing class,
  assigned inside a nested if/else within an `if..then begin..end`, hung the
  parser (the assignment target was eaten as a bare implicit-Self method call,
  consuming only the name and leaving `:=`, then the dangling `else` spun
  ParseBlockAST). bug-compiler-hang-on-nested-if-in-begin. }
program test_local_shadows_method_assign;
type
  TFoo = class
    function Child: Integer;            { method whose name a local shadows }
    procedure Run(sel: Integer);
  end;
function TFoo.Child: Integer;
begin
  Result := -1;
end;
procedure TFoo.Run(sel: Integer);
var child: Integer;                     { local shadows method Child }
begin
  if sel > 0 then
  begin
    if sel = 1 then child := 10
    else child := 20;
    if child > 0 then writeln(child);
  end;
end;
var f: TFoo;
begin
  f := TFoo.Create;
  f.Run(1);                             { 10 }
  f.Run(2);                             { 20 }
  writeln(f.Child);                     { -1 — method still callable }
end.
