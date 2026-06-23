program test_typed_const_record;

{ Record typed constants: `const r: TRec = (field: value; ...)` (FPC named-field
  form). Global + routine-local, mixed field types. Sibling of typed-const arrays. }

type
  TPoint = record x, y: Integer; end;
  TMix   = record a: Integer; c: Char; b: Integer; end;

const
  o: TPoint = (x: 3; y: 4);
  q: TMix   = (a: 10; c: 'Z'; b: 20);

procedure local;
const li: TPoint = (x: 100; y: 200);
begin
  writeln(li.x + li.y);          { 300 — re-initialised each call }
end;

begin
  writeln(o.x + o.y);            { 7 }
  writeln(q.a, ' ', q.c, ' ', q.b);  { 10 Z 20 }
  local;
  local;
end.
