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

  ROW 3 MOVED OUT 2026-09-09, and the comment above is why it is worth saying
  where it went rather than deleting it. It asserted that `TS40(t)` -- a
  destination no Explicit operator has the capacity for -- reaches the GENERIC
  ShortString Explicit conversion. It noted in the same breath that fpc REFUSES
  that cast, and kept the leniency because the alternative at the time was the
  segfault.

  It was the same mechanism as a real bug. The generic-Explicit fallback that
  served row 3 is exactly what made toperator91 call `ShortString Explicit`
  where fpc calls `ShortString Implicit` -- in fpc 3.2.2 `ExplicitShortString`
  is never incremented anywhere in that program. One rule cannot do both, so
  the fallback is gone: an Explicit operator now serves a frozen-string
  destination only at its OWN capacity, and a cast matching none of them
  retries the IMPLICIT lookup.

  The segfault is still closed, by a diagnostic instead of a wrong conversion:
  see test_conversion_operator_no_capacity_match_is_refused.pas, which is row 3
  under its new (and fpc's) answer, and ROW 3 BELOW, which is the case that
  proves the retry actually retries rather than the refusal simply swallowing
  everything.

  ORACLES: fpc 3.2.2 agrees with every row in this file exactly.
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
    class operator Implicit(const aArg: TTest): ShortString;
  end;

class operator TTest.Explicit(const aArg: TTest): TS80;
begin WriteLn('to80'); Result := 'a'; end;

class operator TTest.Explicit(const aArg: TTest): TS90;
begin WriteLn('to90'); Result := 'b'; end;

class operator TTest.Explicit(const aArg: TTest): ShortString;
begin WriteLn('toSS'); Result := 'c'; end;

class operator TTest.Implicit(const aArg: TTest): ShortString;
begin WriteLn('toSSimp'); Result := 'd'; end;

var
  s80: TS80;
  s90: TS90;
  s40: TS40;
  t: TTest;
begin
  s80 := TS80(t);   WriteLn('got ', s80);   { the exactly-sized conversion }
  s90 := TS90(t);   WriteLn('got ', s90);   { ...and its sibling, not the first declared }
  { ROW 3: no Explicit operator has capacity 40, so the cast is NOT an explicit
    conversion -- it retries the implicit lookup and lands on the generic
    ShortString IMPLICIT one. `toSS` must not appear: the Explicit ShortString
    operator is declared right above and fpc never calls it either. }
  s40 := TS40(t);   WriteLn('got ', s40);
end.
