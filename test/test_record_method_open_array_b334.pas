{ Open-array parameters in RECORD methods (b334).

  `function TR.SumAll(const xs: array of Longint)` was a deliberate loud error
  (the old attempt segfaulted before the unified call-arg path existed). The
  IsArray registration is all the caller needs now — pxx open arrays carry
  their length inline at data-8 and the shared arg builder adapts static
  arrays. Also fixed here: a `[...]` open-array LITERAL argument to an
  instance/record METHOD parsed as a SET literal and crashed
  (r.SumAll([10,20]) — the method arg loops now fork on
  ParamIsOpenArrayScalar/ParamIsVarRecArray like the plain-call path).
  FPC's typshrdh.inc TRect.Union(const Points: array of TPoint) is the
  motivating shape. Verified against FPC. }
program test_record_method_open_array_b334;
{$mode objfpc}{$h+}

type
  TPt = record
    X, Y: Longint;
  end;
  TR = record
    Base: Longint;
    function SumAll(const xs: array of Longint): Longint;
    function SpanX(const pts: array of TPt): Longint;
  end;

function TR.SumAll(const xs: array of Longint): Longint;
var
  i: Integer;
begin
  Result := Base;
  for i := 0 to High(xs) do
    Result := Result + xs[i];
end;

function TR.SpanX(const pts: array of TPt): Longint;
var
  i, lo, hi: Longint;
begin
  lo := pts[0].X;
  hi := pts[0].X;
  for i := 1 to High(pts) do
  begin
    if pts[i].X < lo then lo := pts[i].X;
    if pts[i].X > hi then hi := pts[i].X;
  end;
  Result := hi - lo;
end;

var
  r: TR;
  a: array[0..2] of Longint;
  ps: array[0..2] of TPt;
  i: Integer;
begin
  r.Base := 100;
  a[0] := 1; a[1] := 2; a[2] := 3;
  Writeln('sum=', r.SumAll(a));
  Writeln('lit=', r.SumAll([10, 20]));
  for i := 0 to 2 do begin ps[i].X := i * 7; ps[i].Y := i; end;
  Writeln('span=', r.SpanX(ps));
end.
