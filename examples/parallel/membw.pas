{ SPDX-License-Identifier: 0BSD }
program MemBandwidth;
{ Memory-bound vs compute-bound parallel reduction — the HONEST scaling demo. A
  big Int32 array is reduced two ways:

    plain sum      s := s + a[i]                 ~1 add per 4 bytes read
    heavy per-elem s := s + (a[i]*a[i]) mod P    many ALU ops per 4 bytes read

  The plain sum is limited by MEMORY BANDWIDTH, not cores: every worker waits on
  the same DRAM, so N cores give far less than Nx — sublinear scaling. The heavy
  version does more arithmetic per element (higher arithmetic intensity), so a
  larger share of its time is compute that DOES parallelize. Running both over the
  SAME array shows why "more workers" is not a universal speed knob: the speedup
  you get depends on arithmetic intensity AND on how many cores are actually free
  (a busy box caps everyone — exactly what pwLoadOnce/pwLoadCont respect). See the
  -O3 self-compile-is-memory-bound note. Both reductions are exact, so serial and
  parallel must agree.

  Track B/E (example app). Build --threadsafe. }

uses palparallel, baseunix;

const
  N = 40000000;          { 40M Int32 = 160 MB — well past cache }
  P = 1000003;

type TBuf = array[0..N-1] of Integer;
var A: TBuf;             { global (BSS-backed); read-only in the parallel bodies }

function NowUsec: Int64;
var tv: TTimeVal;
begin
  if fpgettimeofday(@tv, nil) = 0 then NowUsec := tv.tv_sec * 1000000 + tv.tv_usec
  else NowUsec := 0;
end;

procedure PlainSum(serial: Boolean; var oSum: Int64);
var i: Integer; s: Int64;
begin
  s := 0;
  if serial then PXXSetParForWorkers(1);
  parallel(pdChunked) for i := 0 to N-1 reduction(+: s) do s := s + A[i];
  if serial then PXXSetParForWorkers(0);
  oSum := s;
end;

procedure HeavySum(serial: Boolean; var oSum: Int64);
var i: Integer; s: Int64;
begin
  s := 0;
  if serial then PXXSetParForWorkers(1);
  parallel(pdChunked) for i := 0 to N-1 reduction(+: s) do
    s := s + (Int64(A[i]) * A[i]) mod P;
  if serial then PXXSetParForWorkers(0);
  oSum := s;
end;

var
  i: Integer;
  t0, t1, usPlainS, usPlainP, usHeavyS, usHeavyP: Int64;
  plainS, plainP, heavyS, heavyP: Int64;
begin
  writeln('Memory vs compute reduction over ', N, ' Int32 (', (N * 4) div 1048576, ' MB)   workers=', PXXParForWorkers);
  for i := 0 to N-1 do A[i] := (i * 2654435761) and $FFFF;

  t0 := NowUsec; PlainSum(True,  plainS); t1 := NowUsec; usPlainS := t1 - t0;
  t0 := NowUsec; PlainSum(False, plainP); t1 := NowUsec; usPlainP := t1 - t0;
  t0 := NowUsec; HeavySum(True,  heavyS); t1 := NowUsec; usHeavyS := t1 - t0;
  t0 := NowUsec; HeavySum(False, heavyP); t1 := NowUsec; usHeavyP := t1 - t0;

  if usPlainS <= 0 then usPlainS := 1;
  if usPlainP <= 0 then usPlainP := 1;
  if usHeavyS <= 0 then usHeavyS := 1;
  if usHeavyP <= 0 then usHeavyP := 1;

  writeln('plain sum  : serial ', usPlainS, ' us   parallel ', usPlainP,
          ' us   speedup ', (usPlainS * 100) div usPlainP, ' /100x   (memory-bound)');
  writeln('heavy sum  : serial ', usHeavyS, ' us   parallel ', usHeavyP,
          ' us   speedup ', (usHeavyS * 100) div usHeavyP, ' /100x   (compute-bound)');
  writeln('sums: plain=', plainS, ' heavy=', heavyS);

  if (plainP = plainS) and (heavyP = heavyS) then
    writeln('ALL AGREE — parallel reductions match serial')
  else begin
    writeln('MISMATCH — reduction not deterministic (BUG)'); Halt(1);
  end;
end.
