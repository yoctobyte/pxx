program test_conversion_operator_result_capacity_is_part_of_its_identity;
{$mode delphi}
{ `class operator Explicit(...): String[80]` and `: String[90]` were ONE result
  type -- the duplicate-conversion check and the conversion lookup both asked
  only Ord(RetType), which is a frozen-string kind for every capacity. So the
  pair was refused as a duplicate, and fpc 3.2.2 compiles it and sends each cast
  to its own operator.

  ROW 3 IS THE ONE THAT MATTERS MOST and it is not the feature: a destination
  with NO matching capacity must still reach the GENERIC ShortString conversion.
  The first cut of this fix treated capacity as a FILTER rather than a rank, and
  because a bare `ShortString` result records DEFAULT_STR_CAP (255) and not 0,
  the generic fallback was excluded -- `TS40(t)` found no operator, fell through
  to a raw record-to-string store and SEGFAULTED where the pinned compiler
  printed the conversion. A row that only asserted the new capability would have
  been green throughout that.

  ORACLES, PER ROW, because they are not the same:
    rows 1-2  fpc 3.2.2 agrees exactly -- `to80 / got a / to90 / got b`.
    row 3     fpc REFUSES (`Illegal type conversion: "TTest" to "TS40"`) and pxx
              takes it through the generic ShortString conversion. Accepting
              what fpc rejects is not a defect (CLAUDE.md), and this is not new
              behaviour being claimed: the PINNED compiler runs this shape
              correctly when the sized pair is removed. The row is here as a
              REGRESSION guard, not as a feature.
  Positive control: the pinned compiler refuses this whole file with
  `duplicate conversion operator`, so the fixture cannot pass by doing nothing. }
type
  TS80 = String[80];
  TS90 = String[90];
  TS40 = String[40];

  TTest = record
    class operator Explicit(const aArg: TTest): TS80;
    class operator Explicit(const aArg: TTest): TS90;
    class operator Explicit(const aArg: TTest): ShortString;
  end;

class operator TTest.Explicit(const aArg: TTest): TS80;
begin WriteLn('to80'); Result := 'a'; end;

class operator TTest.Explicit(const aArg: TTest): TS90;
begin WriteLn('to90'); Result := 'b'; end;

class operator TTest.Explicit(const aArg: TTest): ShortString;
begin WriteLn('toSS'); Result := 'c'; end;

var
  s80: TS80;
  s90: TS90;
  s40: TS40;
  t: TTest;
begin
  s80 := TS80(t);   WriteLn('got ', s80);   { the exactly-sized conversion }
  s90 := TS90(t);   WriteLn('got ', s90);   { ...and its sibling, not the first declared }
  s40 := TS40(t);   WriteLn('got ', s40);   { no String[40] conversion -> the GENERIC one }
end.
