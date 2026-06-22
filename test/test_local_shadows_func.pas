program test_local_shadows_func;

{ bug-impl-prescan-codegen-regression: a local variable whose name matches a
  (case-insensitively named) paramless function must SHADOW the function, both
  when read in an expression and when assigned. The defect compiled `count`
  reads/writes inside Work as calls to the function `Count`, so the counter never
  accumulated (the sat-library "0 clauses" / zlib stored-block miscompile). }

var g: Integer;

function Count: Integer;       { paramless function; collides with locals below }
begin
  Result := g;
end;

procedure Work;
var count, i: Integer;          { `count` must shadow function `Count` here }
begin
  count := 0;                   { assignment to the local, not a call to Count }
  for i := 1 to 7 do
    count := count + 1;         { read + write the local */ not Count() */ }
  g := count;                   { read the local in an expression }
end;

function Tally(n: Integer): Integer;
var count: Integer;             { with params too (read side, ParseFactor) }
begin
  count := n;
  count := count * 2;
  Tally := count;
end;

begin
  Work;
  WriteLn('count=', g, ' viaFunc=', Count);   { 7 7  (Count reads g=7) }
  WriteLn('tally=', Tally(10));               { 20 }
end.
