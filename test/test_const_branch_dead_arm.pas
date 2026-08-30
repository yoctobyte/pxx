program test_const_branch_dead_arm;
{ The same defect from the PASCAL frontend, because the fix is in the shared IR
  and a C-only test would not say so.

  `external name` on a symbol nothing defines is the Pascal spelling of the
  C static-assert idiom: the reference is only emitted if the dead arm survives
  to codegen, and if it is emitted the binary dies BEFORE the first WriteLn with
  `symbol lookup error`. So these externals are load-bearing and must stay
  undefined -- defining them deletes the test while leaving it green.

  FPC IS NOT THE ORACLE HERE and the difference is the interesting direction:
  fpc 3.2.2 does NOT prune these arms either, so it fails to LINK this file
  outright. gcc does prune the equivalent C (see c_const_branch_dead_arm.c,
  which diffs against it), and gcc is the oracle for the behaviour. Do not
  "fix" this toward FPC by defining the symbols -- that deletes the test.
  bug-a-a-constant-if-condition-keeps-its-dead-arm-and-the-binary-will-not-start }
function NEVER_true: Integer;   external name 'PXX_NEVER_DEFINED_true';
function NEVER_false: Integer;  external name 'PXX_NEVER_DEFINED_false';
function NEVER_sizeof: Integer; external name 'PXX_NEVER_DEFINED_sizeof';

function f1(x: Integer): Integer;
begin if True then begin f1 := x + 1; Exit; end; f1 := NEVER_true; end;

function f2(x: Integer): Integer;
begin if False then begin f2 := NEVER_false; Exit; end; f2 := x + 1; end;

{ The condition is a constant COMPARISON, not a literal: SizeOf folds to a
  const_int on both arms and the `=` around them did not fold with it. }
function f3(x: Integer): Integer;
begin if SizeOf(LongInt) = 4 then begin f3 := x + 1; Exit; end; f3 := NEVER_sizeof; end;

{ NEGATIVE CONTROL — a runtime condition must still branch both ways. A fold
  that fired here would silently invert control flow, a worse defect than the
  one being fixed. }
function r1(x: Integer): Integer;
begin if x = 4 then r1 := 100 else r1 := 200; end;
function r2(x: Integer): Integer;
begin if x <> 4 then r2 := 300 else r2 := 400; end;

begin
  WriteLn(f1(41), ' ', f2(41), ' ', f3(41));
  WriteLn(r1(4), ' ', r1(5), ' ', r2(4), ' ', r2(5));
end.
