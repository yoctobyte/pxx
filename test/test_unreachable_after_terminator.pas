{ STATEMENTS AFTER AN UNCONDITIONAL TRANSFER ARE NOT EMITTED, at every -O level.

  gcc, clang and tcc all drop them at -O0 with no optimiser asked for, and tcc
  has no optimiser at all, which is what makes this LOWERING rather than an
  optimisation (decide-should-unreachable-code-that-breaks-the-LOAD-be-pruned-at-O0).
  The `if`/`while` half landed first; this is the third shape that ticket listed
  and it is a DIFFERENT mechanism: sequence reachability inside AN_SEQ, not a
  constant condition.

  never_term_P is declared and never defined, so an unreachable call to it is
  observable the only way an unreachable call can be -- the binary links and
  then fails to start with `undefined symbol'. Before this, that is exactly what
  happened at -O0 (IROptDeadCode caught it from -O1 up).

  THE LABEL ROWS ARE THE GUARD'S POSITIVE CONTROL and they are the entire risk
  of this pass: `goto` can land after a terminator, so a label anywhere in the
  unreachable remainder has to keep it. Row 4 jumps FORWARD over an Exit into
  the statements behind it; if the prune ignored labels, that label would not
  exist and the goto would have nowhere to land -- which the compiler reports
  rather than miscompiling, so a broken guard fails loudly here.

  Break and Continue are terminators too and rows 2 and 3 cover them: they leave
  the rest of the loop BODY, so the statements behind them are as unreachable as
  the ones behind an Exit. They differ in how often the body runs, which is why
  the expected count below is 5 and not 3 -- Break leaves the loop after one
  iteration, Continue leaves only the iteration and so runs all three. Deliberately NOT treated as terminators: a call to a routine
  that never returns (a property of the callee, not of the node) and an `if`
  whose arms both terminate. }
program test_unreachable_after_terminator;
var n, hits: Integer;

function NeverTerm: Integer; external name 'never_term_P';

{ row 1: after Exit }
procedure AfterExit;
begin
  Inc(hits);
  Exit;
  WriteLn(NeverTerm);
end;

{ row 2: after Break }
procedure AfterBreak;
var i: Integer;
begin
  for i := 1 to 3 do
  begin
    Inc(hits);
    Break;
    WriteLn(NeverTerm);
  end;
end;

{ row 3: after Continue }
procedure AfterContinue;
var i: Integer;
begin
  for i := 1 to 3 do
  begin
    Inc(hits);
    Continue;
    WriteLn(NeverTerm);
  end;
end;

{ row 4: THE GUARD. A label sits behind an Exit and a goto reaches it, so the
  statements after that Exit must survive. }
procedure LabelBehindExit;
label fwd;
begin
  n := 0;
  goto fwd;
  Exit;
fwd:
  n := 7;
end;

{ row 5: the same guard on Pascal's `case`, which builds AN_CASE just as C's
  switch does. Every arm exits, so the arm behind each Exit is unreachable while
  the ARM LABEL behind it is not -- the shape that made the C half reject crtl. }
function Pick(x: Integer): Integer;
begin
  Pick := -1;
  case x of
    1: begin Pick := 10; Exit; end;
    2: begin Pick := 20; Exit; end;
  else
    begin Pick := 99; Exit; end;
  end;
end;

begin
  hits := 0;
  AfterExit;
  AfterBreak;
  AfterContinue;
  { 1 from AfterExit + 1 from AfterBreak + 3 from AfterContinue }
  if hits <> 5 then
  begin WriteLn('FAIL: hits=', hits, ' want 5'); Halt(1); end;
  LabelBehindExit;
  if n <> 7 then
  begin WriteLn('FAIL: the label behind Exit was pruned, n=', n, ' want 7'); Halt(1); end;
  if (Pick(1) <> 10) or (Pick(2) <> 20) or (Pick(5) <> 99) then
  begin
    WriteLn('FAIL: a case arm behind an Exit was pruned: ',
            Pick(1), ' ', Pick(2), ' ', Pick(5), ' want 10 20 99');
    Halt(1);
  end;
  WriteLn('AFTERTERM OK');
end.
