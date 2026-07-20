{ SPDX-License-Identifier: 0BSD }
program PrimeCountParallel;
{ Prime counting over [2..N] — the EVEN-LOAD integer foil to collatz.pas.

  Collatz has an erratic per-item cost, so the distribution policy decides the
  outcome. Trial division is the opposite: the cost of IsPrime(n) grows smoothly
  with sqrt(n), so a contiguous pdChunked split is already close to balanced and
  pdOnDemand buys almost nothing. Running both here makes that visible — the
  policy earns its keep only when the load is uneven.

  Two reductions in one pass:
    reduction(+:   primes) — pi(N), the prime count.
    reduction(max: maxGap) — the largest gap between consecutive primes.
  The gap is derived by GapBefore(n), a PURE function of n (it walks back to the
  previous prime), so it does not depend on where the slice boundaries fall — the
  max is exact regardless of worker count, and both reductions are asserted
  against known constants.

  Safe pattern: IsPrime is a FUNCTION, so its scratch lives on the worker's own
  stack (private). Nothing shared is written from the body except the reduction
  variables.

  Track B/E (example app). Build --threadsafe. }

uses palparallel, baseunix;

const
  N        = 2000000;
  PI_N     = 148933;     { pi(2*10^6)          — known value, correctness oracle }
  MAXGAP   = 132;        { max prime gap below 2*10^6 — ditto }

function IsPrime(n: Integer): Boolean;
var d: Integer;
begin
  if n < 2 then begin IsPrime := False; Exit; end;
  if n < 4 then begin IsPrime := True; Exit; end;
  if (n and 1) = 0 then begin IsPrime := False; Exit; end;
  d := 3;
  while d * d <= n do
  begin
    if (n mod d) = 0 then begin IsPrime := False; Exit; end;
    d := d + 2;
  end;
  IsPrime := True;
end;

{ Distance from n back to the previous prime — a pure function of n, so it stays
  private per worker and needs no cross-iteration state. Only evaluated when n
  itself is prime, so the walk is short. }
function GapBefore(n: Integer): Integer;
var p: Integer;
begin
  p := n - 1;
  while (p >= 2) and not IsPrime(p) do p := p - 1;
  if p < 2 then GapBefore := 0 else GapBefore := n - p;
end;

function NowUsec: Int64;
var tv: TTimeVal;
begin
  if fpgettimeofday(@tv, nil) = 0 then NowUsec := tv.tv_sec * 1000000 + tv.tv_usec
  else NowUsec := 0;
end;

{ Count primes in [2..N] under a chosen distribution / worker count, and track
  the largest prime gap. Reduction variables are ENCLOSING LOCALS (globals are
  not captured); results leave via out params. }
procedure CountPrimes(useOnDemand, forceSerial: Boolean; var oCount, oGap: Int64);
var n: Integer; lCount, lGap: Int64;
begin
  lCount := 0; lGap := 0;
  if forceSerial then PXXSetParForWorkers(1);
  if useOnDemand then
    parallel(pdOnDemand) for n := 2 to N reduction(+: lCount) reduction(max: lGap) do
    begin
      if IsPrime(n) then
      begin
        lCount := lCount + 1;
        { Second GapBefore call only runs on a NEW maximum — a few dozen times
          over the whole range — so the recompute is free in practice. }
        if GapBefore(n) > lGap then lGap := GapBefore(n);
      end;
    end
  else
    parallel(pdChunked) for n := 2 to N reduction(+: lCount) reduction(max: lGap) do
    begin
      if IsPrime(n) then
      begin
        lCount := lCount + 1;
        { Second GapBefore call only runs on a NEW maximum — a few dozen times
          over the whole range — so the recompute is free in practice. }
        if GapBefore(n) > lGap then lGap := GapBefore(n);
      end;
    end;
  if forceSerial then PXXSetParForWorkers(0);
  oCount := lCount; oGap := lGap;
end;

var
  t0, t1, usSerial, usChunked, usOnDemand: Int64;
  cSerial, cChunked, cOnDemand: Int64;
  gSerial, gChunked, gOnDemand: Int64;
  bad: Boolean;
begin
  writeln('Prime count over 2..', N, '   workers=', PXXParForWorkers);

  t0 := NowUsec; CountPrimes(False, True,  cSerial,   gSerial);   t1 := NowUsec; usSerial   := t1 - t0;
  t0 := NowUsec; CountPrimes(False, False, cChunked,  gChunked);  t1 := NowUsec; usChunked  := t1 - t0;
  t0 := NowUsec; CountPrimes(True,  False, cOnDemand, gOnDemand); t1 := NowUsec; usOnDemand := t1 - t0;

  if usSerial   <= 0 then usSerial   := 1;
  if usChunked  <= 0 then usChunked  := 1;
  if usOnDemand <= 0 then usOnDemand := 1;

  writeln('primes     = ', cSerial, '   max gap = ', gSerial);
  writeln('serial     : ', usSerial, ' us');
  writeln('pdChunked  : ', usChunked, ' us   speedup ', (usSerial * 100) div usChunked, ' /100x');
  writeln('pdOnDemand : ', usOnDemand, ' us   speedup ', (usSerial * 100) div usOnDemand, ' /100x');
  writeln('(even load: pdChunked ~= pdOnDemand here, unlike collatz)');

  bad := False;
  if (cChunked <> cSerial) or (cOnDemand <> cSerial) then
  begin
    writeln('MISMATCH — prime count differs by distribution (BUG)'); bad := True;
  end;
  if (gChunked <> gSerial) or (gOnDemand <> gSerial) then
  begin
    writeln('MISMATCH — max-gap reduction differs by distribution (BUG)'); bad := True;
  end;
  if cSerial <> PI_N then
  begin
    writeln('WRONG — pi(', N, ') should be ', PI_N, ' (BUG)'); bad := True;
  end;
  if gSerial <> MAXGAP then
  begin
    writeln('WRONG — max gap should be ', MAXGAP, ' (BUG)'); bad := True;
  end;
  if bad then Halt(1);
  writeln('ALL AGREE — count matches pi(N), reductions identical across distributions');
end.
