program test_case_arm_finalize_shape;
{ The IR-SHAPE probe behind test_case_arm_temp_finalize. Not run — READ.

  `Hot` is deliberately the smallest case statement that builds a managed-record
  temp in exactly one arm. The Makefile row dumps `PXXDBG=a.ir:Hot` and asks
  whether the last copy_rec_managed comes before or after the last label:

    AFTER-MERGE          the finalize is in the merge block — the bug
    IN-ARM               the finalize is inside the arm that built the temp
    NO-FINALIZE-EMITTED  nothing was built, so the row is not aimed at anything

  The third is why this program exists separately rather than reusing the leak
  test: it has ONE managed arm and one entry point, so the probe's subject is
  unambiguous, and if a future change stops emitting the finalize here the row
  says so instead of quietly passing. `Hot` is never called with 1, on purpose —
  the whole point is the cost paid by the arms that build nothing.
  bug-a-a-case-arm-finalizes-its-managed-temp-after-the-merge }
{$mode objfpc}{$H+}
uses sysutils;

type TR = record S: AnsiString; K: Integer; end;

var sink: Integer;

function MkR(n: Integer): TR;
begin
  MkR.S := 'r' + IntToStr(n);
  MkR.K := n;
end;

procedure TakeR(a: TR);
begin
  Inc(sink, Length(a.S) + a.K);
end;

procedure Hot(k: Integer);
begin
  case k of
    0: Inc(sink);
    1: TakeR(MkR(k));
  else Inc(sink, 2);
  end;
end;

begin
  sink := 0;
  Hot(0);
  WriteLn('sink=', sink);
end.
