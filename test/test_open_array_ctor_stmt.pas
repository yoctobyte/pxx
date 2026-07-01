program test_open_array_ctor_stmt;

function f(const a: array of integer): integer;
begin
  f := Length(a);
end;

procedure p(const a: array of integer);
var i: integer;
begin
  for i := 0 to High(a) do
    write(a[i], ' ');
  writeln;
end;

var r: integer;
begin
  r := f([1, 2, 3]);   { expression context, already worked }
  writeln(r);
  f([4, 5]);           { statement context, result discarded }
  p([1, 2, 3]);        { procedure, statement-only }
  p([]);               { empty ctor, statement context }
end.
