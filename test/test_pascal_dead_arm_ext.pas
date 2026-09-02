{ THE LINK-TIME HALF, and it is the one that actually failed.

  `never_defined_P` is declared and never defined anywhere. Both guards below
  are constant-false, so under Pascal's short-circuit rule the call is not
  evaluated -- but before the parser folded the condition, the dead arm was
  still EMITTED, the external became a real reference, and the binary died
  before `main`:

    -O0/-O2/-O3: symbol lookup error: undefined symbol: never_defined_P (127)

  All three levels, which is why this is a LOWERING test and not an optimiser
  one. This program cannot pass by accident: if the fold regresses, it does not
  print the wrong thing, it fails to start.
  feature-a-fold-the-consensus-dead-branch-core-at-every-level }
program test_pascal_dead_arm_ext;
function NeverDefinedP: Integer; cdecl; external name 'never_defined_P';
begin
  if False and (NeverDefinedP = 0) then WriteLn('unreachable-x');
  if (False or False) or (not True) then WriteLn('unreachable-y');
  WriteLn('DEADARM OK');
end.
