{ `-OO` IS THE SOURCE-1:1 REFERENCE, and this file is the reason it exists.

  -O0 used to be that reference. It stopped being one when the constant-condition
  dead-arm prune and the short-circuit folds moved into lowering, where gcc,
  clang and tcc all put them (tcc has no optimiser at all, which is what settles
  that they are lowering rather than optimisation). The 1:1 build had to move
  somewhere rather than disappear, because separating a LOWERING bug from an
  OPTIMIZER bug is the entire reason -O0's charter said 1:1 -- so it moved to a
  NAMED FLAG, never a level below zero (decide-the-o-level-charter: an author
  must choose WHICH trade, not HOW MUCH).

  THE -OO ROW ASSERTS A FAILURE, AND THAT IS THE POINT. `never_oo_P` is declared
  and never defined, so a compiler that EMITS the unreachable call produces a
  binary that dies before main with `undefined symbol`, while one that prunes it
  runs. A flag that silently did nothing would pass a row asserting success, and
  the test would certify a flag that does not exist. Failure is the only
  observation that distinguishes the two.

  So, deliberately inverted against every other row in this suite:
      -O0   runs, prints SOURCE1TO1 OK   (the arm was pruned)
      -OO   fails to start                (the arm was emitted, 1:1 with source)
  feature-a-fold-the-consensus-dead-branch-core-at-every-level part 3 }
program test_source_one_to_one_oo;
function NeverOO: Integer; external name 'never_oo_P';
begin
  if False then WriteLn(NeverOO);
  while False do WriteLn(NeverOO);
  WriteLn('SOURCE1TO1 OK');
end.
