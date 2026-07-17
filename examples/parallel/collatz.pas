{ SPDX-License-Identifier: 0BSD }
program CollatzParallel;
{ Collatz (hailstone) step counts — a PURELY INTEGER parallel demo showing why
  the work-distribution policy matters. For each n in [1..N] count the steps of
  n -> (n/2 if even else 3n+1) until it reaches 1, and reduce the total.

  The per-item cost is WILDLY uneven (some n stop in a few steps, some in
  hundreds), so this is exactly where the distribution policy earns its keep:
    - pdChunked  (contiguous split) : one worker inherits a hot stripe -> poor.
    - pdOnDemand (work stealing)    : free workers grab more -> better balance.
  We reduce the total three ways (serial / chunked / on-demand), print the
  wall-clock speedups, and assert all three totals AGREE — a data-parallel
  reduction must be deterministic regardless of worker count or split. Int64
  keeps 3n+1 and the sum exact, so it is bit-identical.

  Note the safe pattern: `Collatz(n)` is a FUNCTION, so its scratch lives on the
  worker's own stack (private); its result folds straight into the reduction
  variable. The loop body keeps no shared temporary — a captured local written by
  every worker would be a data race (see the parallel-for capture notes).

  Track B/E (example app). Build --threadsafe. }

uses palparallel, baseunix;

const N = 3000000;

function Collatz(n: Int64): Int64;
var s: Int64;
begin
  s := 0;
  while n <> 1 do
  begin
    if (n and 1) = 0 then n := n div 2 else n := 3 * n + 1;
    s := s + 1;
  end;
  Collatz := s;
end;

function NowUsec: Int64;
var tv: TTimeVal;
begin
  if fpgettimeofday(@tv, nil) = 0 then NowUsec := tv.tv_sec * 1000000 + tv.tv_usec
  else NowUsec := 0;
end;

{ Sum Collatz(n) over [1..N] under a chosen distribution / worker count.
  The reduction variable is an ENCLOSING LOCAL (globals are not captured);
  the total is returned via an out param. }
procedure SumSteps(useOnDemand, forceSerial: Boolean; var oTot: Int64);
var n: Integer; lTot: Int64;
begin
  lTot := 0;
  if forceSerial then PXXSetParForWorkers(1);
  if useOnDemand then
    parallel(pdOnDemand) for n := 1 to N reduction(+: lTot) do lTot := lTot + Collatz(n)
  else
    parallel(pdChunked) for n := 1 to N reduction(+: lTot) do lTot := lTot + Collatz(n);
  if forceSerial then PXXSetParForWorkers(0);
  oTot := lTot;
end;

var
  t0, t1, usSerial, usChunked, usOnDemand: Int64;
  totSerial, totChunked, totOnDemand: Int64;
begin
  writeln('Collatz step-count sum over 1..', N, '   workers=', PXXParForWorkers);

  t0 := NowUsec; SumSteps(False, True,  totSerial);   t1 := NowUsec; usSerial   := t1 - t0;
  t0 := NowUsec; SumSteps(False, False, totChunked);  t1 := NowUsec; usChunked  := t1 - t0;
  t0 := NowUsec; SumSteps(True,  False, totOnDemand); t1 := NowUsec; usOnDemand := t1 - t0;

  if usSerial   <= 0 then usSerial   := 1;
  if usChunked  <= 0 then usChunked  := 1;
  if usOnDemand <= 0 then usOnDemand := 1;

  writeln('total steps = ', totSerial);
  writeln('serial     : ', usSerial, ' us');
  writeln('pdChunked  : ', usChunked, ' us   speedup ', (usSerial * 100) div usChunked, ' /100x');
  writeln('pdOnDemand : ', usOnDemand, ' us   speedup ', (usSerial * 100) div usOnDemand, ' /100x');

  if (totChunked = totSerial) and (totOnDemand = totSerial) then
    writeln('ALL AGREE — every distribution gives the identical sum')
  else begin
    writeln('MISMATCH — reduction not deterministic (BUG)'); Halt(1);
  end;
end.
