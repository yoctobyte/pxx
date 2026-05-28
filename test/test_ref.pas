program test_ref;

procedure Foo(const name: string);
begin
  writeln(name);
end;

procedure Bar(const name: string);
begin
  Foo(name);
end;

begin
  Bar('hello');
end.
