program test_conversion_operator_ambiguous_cast_is_refused;
{$mode delphi}
{ Two SIZED conversion results, no generic one, and a cast to a third capacity.
  There is nothing to prefer, and pxx refuses rather than picking.

  fpc 3.2.2 refuses it too -- `Illegal type conversion: "TTest" to "TS40"`.
  Different wording, same verdict; a differing diagnostic is deferred, not a
  defect.

  THIS FIXTURE EXISTS BECAUSE THE ARM IT COVERS DEPENDS ON SOMEONE ELSE'S
  MECHANISM. The refusal is driven by FindOpConvRankedAmb's tie counter
  (`nBest`), which is shared with the implicit store path and with the
  declaration-time duplicate check. A change there that stops counting these
  ties does not fail anywhere visible -- it turns this refusal into a silent
  pick of whichever operator was scanned first, which is the accepted-invalid
  shape this whole family keeps producing. Reads WHICH refusal, because the
  no-conversion message is a different rule and would otherwise pass here.
  bug-p-an-explicit-cast-with-no-capacity-match-falls-back-to-the-wrong-conversion-operator }
type
  TS80 = String[80];
  TS90 = String[90];
  TS40 = String[40];

  TTest = record
    class operator Implicit(const aArg: TTest): TS80;
    class operator Implicit(const aArg: TTest): TS90;
  end;

class operator TTest.Implicit(const aArg: TTest): TS80;
begin WriteLn('imp80'); Result := 'a'; end;

class operator TTest.Implicit(const aArg: TTest): TS90;
begin WriteLn('imp90'); Result := 'b'; end;

var
  s40: TS40;
  t: TTest;
begin
  s40 := TS40(t);
  WriteLn('got ', s40);
end.
