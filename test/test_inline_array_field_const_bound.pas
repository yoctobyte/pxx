program test_inline_array_field_const_bound;
{ bug-inline-array-field-const-bound: an inline anonymous array field whose
  subrange bounds are constant EXPRESSIONS (`0..N - 1`) must parse — before
  the fix only literal bounds worked in record-field position and this failed
  with `Expected: ], but got: N`. Covers 1-D, N-D and class-field variants. }
const
  N = 8;
  W = 2 + 1;
type
  TE = record v: Integer; end;
  TC = record
    slots: array[0..N - 1] of TE;          { const-expr high bound }
    grid: array[0..W - 1, 1..W] of Integer; { N-D, const-expr in both dims }
  end;
  TK = class
  public
    ring: array[0..N div 2 - 1] of Integer; { class-field path, div expr }
  end;
var
  c: TC;
  k: TK;
  i, s: Integer;
begin
  for i := 0 to N - 1 do
    c.slots[i].v := i * 10;
  writeln(c.slots[0].v);
  writeln(c.slots[N - 1].v);
  s := 0;
  for i := 1 to W do
  begin
    c.grid[W - 1, i] := i;
    s := s + c.grid[W - 1, i];
  end;
  writeln(s);
  k := TK.Create;
  for i := 0 to N div 2 - 1 do
    k.ring[i] := i + 100;
  writeln(k.ring[N div 2 - 1]);
  k.Free;
end.
