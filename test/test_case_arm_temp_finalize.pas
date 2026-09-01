program test_case_arm_temp_finalize;
{ A `case` arm's managed temp is finalized IN THE ARM, not after the merge.

  AN_IF flushes IRFlushPostCallIntf per arm; AN_CASE did not. A `case` is ONE
  statement, so a by-value managed-record or interface temp built in one arm had
  its finalize emitted after the merge label and ran on EVERY path through the
  statement, including the arms that built nothing. Same defect
  bug-a-managed-temps-for-an-untaken-branch-are-still-init-and-finalized fixed
  for `if`; `case` was never covered.

  It is COST, not corruption: the temp is nil-inited, so the stray finalize is a
  heap-lock round trip that releases nothing. The cost is not small.

  THE CONTROL IS THE OTHER SPELLING, which is what makes the number mean
  something. The same three-way dispatch written with `if`/`else if` was ALREADY
  fast on the pre-fix binary, because AN_IF already had the flush:

    20M calls of `Hot(0)` — the arm that allocates is never taken
      case, pre-fix binary   1.75 1.76 1.77 1.78 1.78 s
      case, fixed binary     0.24 0.24 0.24 0.24 0.25 s
      if,   pre-fix binary   0.23 0.23 0.24 s          <- the control
    Interleaved, min of five, same machine, same source, sink=20000000 on all
    three and on FPC.

  So `case` paid 7.3x for a finalize the `if` spelling never emitted, and the fix
  lands it exactly on the `if` timing rather than somewhere better — which is the
  reading that says this removed the stray work and did not add anything.

  WHAT THIS PROGRAM CAN AND CANNOT CATCH, because it is not the same thing.

  The leak bound and the output row read IDENTICALLY on the pre-fix binary --
  2369/2364 live=5, sink=502445 -- and they must, because a stray finalize on a
  nil-inited temp releases nothing. A row that cannot fail is not a guard, so
  this program does NOT guard the fix. It guards the OPPOSITE direction: moving
  a finalize earlier is a double free if it lands in the wrong arm, and that this
  program would catch, which is why every arm is taken many times and why it runs
  under -dPXX_HEAP_DEBUG.

  The fix itself is guarded by an IR-SHAPE assertion in the Makefile beside this,
  which reads `PXXDBG=a.ir:Hot` and asks whether the last copy_rec_managed comes
  before or after the last label. That one DOES discriminate: AFTER-MERGE on the
  pre-fix binary, IN-ARM on the fixed one, and NO-FINALIZE-EMITTED on a case with
  no managed temp at all -- which the harness treats as a failure of AIM rather
  than a pass, because a comparison whose subject never ran cannot fail either.

  The timing above is not re-run anywhere; it is a wall clock and this tier does
  not measure those.
  bug-a-a-case-arm-finalizes-its-managed-temp-after-the-merge }
{$mode objfpc}{$H+}
uses sysutils;

const N = 1000;

type
  TR = record S: AnsiString; K: Integer; end;
  IThing = interface ['{11111111-2222-3333-4444-555555555555}']
    function Id: Integer;
  end;
  TThing = class(TInterfacedObject, IThing)
  public
    N: Integer;
    function Id: Integer;
  end;

var i, sink: Integer;

function TThing.Id: Integer;
begin
  Id := N;
end;

function MkR(n: Integer): TR;
begin
  MkR.S := 'r' + IntToStr(n);
  MkR.K := n;
end;

function MkIntf(n: Integer): IThing;
var t: TThing;
begin
  t := TThing.Create;
  t.N := n;
  MkIntf := t;
end;

procedure TakeR(a: TR);            begin Inc(sink, Length(a.S) + a.K); end;
procedure TakeI(const a: IThing);  begin Inc(sink, a.Id); end;

begin
  sink := 0;
  for i := 1 to N do
    case i mod 4 of
      0: Inc(sink);                 { builds nothing — used to pay anyway }
      1: TakeR(MkR(i));             { managed record temp }
      2: TakeI(MkIntf(i));          { interface temp }
    else
      begin TakeR(MkR(i)); TakeI(MkIntf(i)); end;
    end;
  WriteLn('sink=', sink);
end.
