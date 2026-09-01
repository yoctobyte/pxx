program test_except_arm_finalize_shape;
{ The IR-SHAPE probe behind test_except_arm_temp_finalize. Not run — READ.

  `Hot` is the smallest try/except that builds a managed-record temp inside its
  HANDLER. The Makefile row dumps `PXXDBG=a.ir:Hot` and asks whether the last
  copy_rec_managed comes before or after the last label:

    AFTER-MERGE          the finalize is in the merge block, so it runs on the
                         NO-EXCEPTION path too — the bug
    IN-ARM               the finalize is inside the handler that built the temp
    NO-FINALIZE-EMITTED  nothing was built, so the row is not aimed at anything

  `Hot` is never called in a way that raises, on purpose: the cost this guards is
  paid by the path where the handler never runs at all.
  bug-a-an-exception-handler-arm-finalizes-its-managed-temp-after-the-merge }
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
  try
    Inc(sink);
  except
    on E: Exception do TakeR(MkR(k));
  end;
end;

begin
  sink := 0;
  Hot(0);
  WriteLn('sink=', sink);
end.
