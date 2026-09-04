{ {$ASSERTIONS ON/OFF} and {$C+}/{$C-} must compile the Assert call OUT, not
  make it a runtime no-op.

  THE CONDITION HAS A SIDE EFFECT ON PURPOSE, and that is the whole assertion:
  a test that only checked "nothing printed" passes on a compiler that still
  EVALUATES the condition and merely declines to complain, which is what pxx did
  until 2026-09-04 (measured on v363 and again here: n=1 where FPC gives n=0,
  with no diagnostic either way). Only a condition that leaves a trace can tell
  the two apart.

  THE NUMBERS ARE DELTAS, NOT ABSOLUTES. pxx defaults assertions ON and FPC
  defaults them OFF -- deliberately, because flipping ours would turn every
  existing pxx assertion into dead code silently. So the absolute counts differ
  from FPC by the leading row, while every STEP matches it exactly; run this
  file under `pascal26 --no-assertions` and it prints FPC's column, which
  test-core asserts as its own row.

  Both spellings are exercised because they are two paths to one state: the
  letter switch is dispatched above the directive chain and the long form inside
  it, and a fix to one arm that misses the other is this repo's most-cited
  failure mode. feature-p-assertions-directive-and-position }
program test_assertions_directive_gating;
var n: Integer;

function Bump: Boolean;
begin
  n := n + 1;
  Bump := True;
end;

begin
  n := 0;
  Assert(Bump, 'default');
  WriteLn(n);
  {$ASSERTIONS OFF}
  Assert(Bump, 'off');
  WriteLn(n);
  {$ASSERTIONS ON}
  Assert(Bump, 'on');
  WriteLn(n);
  {$C-}
  Assert(Bump, 'c-minus');
  WriteLn(n);
  {$C+}
  Assert(Bump, 'c-plus');
  WriteLn(n);
end.
