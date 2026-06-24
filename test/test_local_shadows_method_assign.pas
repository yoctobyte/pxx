{ Regression: a local var whose name matches a method of the enclosing class.
  The implicit-Self dispatch ate the assignment target as a bare method call
  (consuming only the name, leaving `:=`). Two symptoms, one root cause:
    - with an `else`: the dangling `else` spun ParseBlockAST forever (HANG)
      — bug-compiler-hang-on-nested-if-in-begin.
    - without an `else`: the `:= rhs` was silently skipped to `;`, leaving the
      local uninitialised (garbage -> segfault with a pointer)
      — bug-method-miscompiled-by-context.
  Fixed by guarding implicit-Self dispatch with `si < 0` (a local shadows the
  method). }
program test_local_shadows_method_assign;
type
  TFoo = class
    function Child: Integer;            { method whose name a local shadows }
    procedure Run(sel: Integer);
    function Pick(a: Integer): Integer;
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
function TFoo.Pick(a: Integer): Integer;
var child: Integer;                     { local shadows method Child (no else) }
begin
  child := 30;
  if a = 2 then child := 40;            { was skipped -> child uninitialised }
  Result := child;
end;
var f: TFoo;
begin
  f := TFoo.Create;
  f.Run(1);                             { 10 }
  f.Run(2);                             { 20 }
  writeln(f.Pick(1));                   { 30 — no-else assignment landed }
  writeln(f.Pick(2));                   { 40 }
  writeln(f.Child);                     { -1 — method still callable }
end.
