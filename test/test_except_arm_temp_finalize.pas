program test_except_arm_temp_finalize;
{ An exception HANDLER arm's managed temp is finalized in the arm.

  Fourth statement kind to need the IRFlushPostCallIntf boundary, after AN_IF's
  arms, the three loop bodies and AN_CASE's arms. A try/except is ONE statement,
  so a by-value managed-record or interface temp built inside a handler had its
  finalize emitted after the merge and ran on the NORMAL path too -- the path
  where nothing was raised and the handler never executed.

  COST on the no-exception path, and the control is again the other spelling:
  5M calls of a try whose handler never runs,
    on E: Exception do TakeR(MkR(k))              0.52 0.54 0.51 s   before
    the same, after the fix                       0.08 0.07 0.08 s
    on E: Exception do if k >= 0 then TakeR(...)  0.07 0.08 0.07 s   <- control
  The if-wrapped spelling was ALREADY fast before the fix, because AN_IF supplies
  the flush and changes nothing else. sink=5000000 on all of them.

  CORRECTNESS is what this program checks, and it is the direction that can
  actually break: a finalize moved earlier is a double free if it moved into the
  wrong arm, and a handler arm has two ways to leave that an `if` arm does not --
  a `raise;` re-raise and an exception escaping the handler. Both are exercised
  here with the temp built BEFORE the leave, so a finalize placed after the leave
  would be skipped (a leak) and one placed under it would run twice.

  NO LEAK BOUND ON THIS PROGRAM, deliberately, and the number is on record so
  nobody reads its absence as an oversight. Per arm, 500 trips:

    Handled     2666/2664 live=2      clean
    NotRaised      1/0    live=1      clean (allocates nothing — no exception)
    ReRaised    2666/2664 live=2      clean
    Escaped     3799/2820 live=979    LEAKS

  The Escaped arm exercises `raise` of a NEW exception from inside a handler,
  which is `bug-a-an-exception-that-escapes-its-handler-or-is-bare-re-raised-
  still-leaks-its-object`, open and blocked on a Track U decision. A bound here
  would be measuring that ticket, not this fix. When it closes, add
  `assert_no_leak ... 50` beside the rows below. The arm stays because a
  mis-placed finalize on a LEAVE path is exactly what this program is for, and
  -dPXX_HEAP_DEBUG catches the double-free direction whether or not a count moves.

  The leak bound could not see the COST anyway -- a stray finalize on a
  nil-inited temp releases nothing -- so the discriminating guard is the IR-shape
  assertion in the Makefile beside this, which reads AFTER-MERGE on the pre-fix
  binary and IN-ARM on the fixed one, and treats NO-FINALIZE-EMITTED as a failure
  of aim.
  bug-a-an-exception-handler-arm-finalizes-its-managed-temp-after-the-merge }
{$mode objfpc}{$H+}
uses sysutils;

const N = 500;

type
  TR = record S: AnsiString; K: Integer; end;
  EMy = class(Exception) end;

var i, sink: Integer;

function MkR(n: Integer): TR;
begin
  MkR.S := 'r' + IntToStr(n);
  MkR.K := n;
end;

procedure TakeR(a: TR);
begin
  Inc(sink, Length(a.S) + a.K);
end;

procedure Handled(k: Integer);
begin
  try
    raise EMy.Create('x');
  except
    on E: EMy do TakeR(MkR(k));
  end;
end;

procedure NotRaised(k: Integer);
begin
  try
    Inc(sink);
  except
    on E: EMy do TakeR(MkR(k));
  end;
end;

procedure ReRaised(k: Integer);
begin
  try
    try
      raise EMy.Create('y');
    except
      on E: EMy do begin TakeR(MkR(k)); raise; end;
    end;
  except
    on E: EMy do Inc(sink);
  end;
end;

procedure Escaped(k: Integer);
begin
  try
    try
      raise EMy.Create('z');
    except
      on E: EMy do begin TakeR(MkR(k)); raise EMy.Create('w'); end;
    end;
  except
    on E: EMy do Inc(sink);
  end;
end;

begin
  sink := 0;
  for i := 1 to N do Handled(i);
  for i := 1 to N do NotRaised(i);
  for i := 1 to N do ReRaised(i);
  for i := 1 to N do Escaped(i);
  WriteLn('sink=', sink);
end.
