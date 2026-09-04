program TestGeneratorRaisePastManagedTemp;
{ bug-a-a-generator-body-raising-past-a-managed-temp-is-not-covered-by-the-unwind-landing-pad

  A hidden managed ARGUMENT TEMP in a STACKLESS GENERATOR step function, in a
  frame an exception unwinds past. The step function's cleanup used to be
  disabled wholesale (`if CurProcIsStackless then Exit;`) because a stackless
  generator's locals are its live state -- but a temp minted during lowering has
  no persistent slot, dies inside one statement, and is an ordinary local in
  every sense. Neither the epilogue nor the unwind landing pad released it.

  THE CONTROL TRIPLE, live at the last census threshold, N=2000 / N=8000, and
  the slope is the measurement (the census prints at geometric thresholds, so a
  raw live count divided by N is wrong):

    raiser body                       before        after
    raise Create(gmsg)      no temp    0.986/raise   0.986/raise   -> now FLAT
    raise Create(gmsg+Chr)  temp       1.871/raise   0.936/raise   -> now FLAT
    Length(gmsg+Chr)=0      no raise   0.986/iter    FLAT (live 2)

  Row three is the discriminator the parent ticket used: the SAME temp in the
  SAME routine was released on the normal path and not on the unwind path. Row
  two is this fix. Row three also went flat, which was not the target -- the
  blanket exit was leaking the step function's temps on the ORDINARY return
  path too.

  ROW ONE WAS A DIFFERENT LEAK AND IS NOW CLOSED. With no temp anywhere, a
  raise that escaped a `for..in` still leaked ~1 block per raise: the generator
  INSTANCE, whose SlFree lived in the loop teardown the unwind skipped. That is
  bug-a-a-generator-instance-is-not-freed-when-an-exception-escapes-the-for-in,
  and it is why this test's bound used to be 3000 rather than 50. The teardown
  is a FINALIZER now, so both rows are flat: live=2 at N=2000 (was 1805, and
  3608 at pin v403, which carries neither fix). Bound tightened to 50 in the
  same commit -- a bound sized around someone else's open leak stops guarding
  yours the moment theirs is fixed. }
uses coroutine, slgen, sysutils;

var gmsg: AnsiString;
    caught: Integer;

function Gen(n: Integer): Integer; generator; stackless;
begin
  yield n;
  raise Exception.Create(gmsg + Chr(65));
end;

procedure Once;
var x: Integer;
begin
  try
    for x in Gen(1) do
      if x = 0 then writeln('never');
  except
    on E: Exception do Inc(caught);
  end;
end;

var i: Integer;
begin
  gmsg := 'hello';
  caught := 0;
  for i := 1 to 2000 do Once;
  writeln('caught=', caught);
end.
