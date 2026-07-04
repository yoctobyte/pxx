{ Implicit (sloppy) locals — feature-implicit-locals-sloppy-switch.
  Compiled with --auto-locals (the CLI switch). Every variable below is
  UNDECLARED: under the switch each first assignment (or for-counter) creates a
  routine-local with its type inferred from the RHS. Exercises int, string,
  arithmetic reuse, counted for, and for-in over an array var. A read of an
  undeclared name (not an assignment target) still errors — covered by the
  negative make-test check, not here. }
program test_auto_locals;
var
  arr: array[0..4] of Integer;   { a real declared var, iterated by an implicit for-in counter }
  pass, total: Integer;
begin
  pass := 0; total := 0;

  { 1. implicit Integer, inferred + reused across assignments }
  n := 41;
  n := n + 1;
  Inc(total); if n = 42 then Inc(pass);

  { 2. implicit AnsiString (managed local — ARC init/cleanup must apply) }
  s := 'hel';
  s := s + 'lo';
  Inc(total); if s = 'hello' then Inc(pass);

  { 3. implicit counted for-counter (created as Integer) }
  sum := 0;
  for i := 1 to 5 do
    sum := sum + i;
  Inc(total); if sum = 15 then Inc(pass);

  { 4. implicit for-in element over a declared array var (tyAuto element) }
  arr[0] := 10; arr[1] := 20; arr[2] := 30; arr[3] := 40; arr[4] := 50;
  acc := 0;
  for v in arr do
    acc := acc + v;
  Inc(total); if acc = 150 then Inc(pass);

  writeln('total ok ', pass, ' / ', total);
end.
