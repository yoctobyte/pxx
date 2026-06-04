program test_managed_result_move;

{ Move semantics for managed function results. A user function returns its
  result already at refcount 1 (the callee retained it via `Result := X` and
  excluded it from scope-exit release), so the caller's `a := F(...)` must MOVE
  it, not retain it again -- retaining leaked one reference per assignment.

  This test guards the correctness side of that change: the move must not
  over-free a value that is still aliased. `t := s` / `b := a` take a real
  reference (the RHS is a variable load, not a fresh call), so reassigning the
  source must leave the alias intact. The loops exercise repeated release of
  the previous owner so a regression that over-frees shows as wrong data. }

{$define PXX_MANAGED_STRING}

function Mk(a, b: AnsiString): AnsiString;
begin
  Mk := a + b;
end;

function MkArr(n: Integer): array of Integer;
var r: array of Integer; i: Integer;
begin
  SetLength(r, n);
  for i := 0 to n - 1 do r[i] := n * 10 + i;
  MkArr := r;
end;

procedure Check(ok: Boolean);
begin
  if ok then writeln(1) else writeln(0);
end;

var
  s, t: AnsiString;
  a, b: array of Integer;
  i: Integer;
begin
  s := Mk('val', '1');     { moved call result }
  t := s;                  { alias: real retain }
  s := Mk('val', '2');     { reassign s; t must survive }
  Check(t = 'val1');
  Check(s = 'val2');
  for i := 1 to 2000 do s := Mk('x', 'y');
  Check(s = 'xy');

  a := MkArr(3);           { moved dynarray result }
  b := a;                  { alias }
  a := MkArr(5);           { reassign a; b must survive }
  Check(Length(b) = 3);
  Check(b[2] = 32);
  Check(Length(a) = 5);
  Check(a[4] = 54);
  for i := 1 to 2000 do a := MkArr(4);
  Check(Length(a) = 4);
  Check(a[3] = 43);
end.
