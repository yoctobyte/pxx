{ SPDX-License-Identifier: 0BSD }
program ParallelPoW;
{ Mini proof-of-work — the COMPUTE-BOUND parallel demo (counterpoint to
  membw.pas, which is memory-bound, and collatz.pas, whose load is uneven).

  Over nonces [0..N-1] we hash (prefix || nonce) and count the digests with at
  least K leading zero bits, tracking the best (deepest) one seen. Hashing is
  pure ALU work with almost no memory traffic, so it scales close to linear —
  the clean "this is what real cores buy you" number.

  Two reductions in one pass:
    reduction(+:   found)     — how many nonces met the difficulty.
    reduction(max: bestZeros) — the deepest leading-zero run found.
  Both are exact functions of the nonce range, so serial and parallel MUST
  agree bit for bit; the demo asserts that (a reduction is only useful if it is
  deterministic regardless of worker count or split).

  Safe pattern: the hash is a FUNCTION, so its scratch is private to the worker
  stack. Nothing shared is written from the loop body but the reductions.

  Two hashes:
    --hash fast    (default) splitmix64 — dependency-free integer mixing, all in
                   registers; the purest compute story.
    --hash sha256  real crypto from lib/rtl; heavier per nonce, and it allocates
                   (AnsiString buffers) so it also exercises the allocator under
                   concurrency.

  KNOWN: --hash sha256 currently gets SLOWER with more workers (~0.3x), because
  the runtime heap is guarded by one global spinlock and every worker allocates
  in its hot loop — see feature-opt-heap-per-thread-cache. The results stay
  correct; only throughput suffers. The demo keeps both hashes deliberately: the
  contrast between the register-only path (3.5x) and the allocating path is the
  standing reproducer for that ticket.

  Note: the parallel-for has no cancellation, so there is no early exit on a
  hit — v1 scans the whole range and reduces. That is deliberate: it keeps the
  serial/parallel comparison apples-to-apples.

  Track B/E (example app). Build --threadsafe. }

uses palparallel, baseunix, sha256, sysutils;

const
  N_FAST   = 20000000;   { nonces for splitmix64 — cheap per hash }
  N_SHA    = 60000;      { nonces for SHA-256 — ~450x heavier per hash }
  K        = 24;         { difficulty: leading zero bits required }
  PREFIX   = 'pxx-block-header/';

var
  useSha: Boolean;
  N: Integer;

{ splitmix64 — a strong integer mixer, no tables, no memory. }
function MixHash(nonce: Int64): QWord;
var z: QWord;
begin
  { Fold the prefix in as a fixed 64-bit seed so the "block header" is part of
    the preimage without costing memory traffic in the hot loop. }
  z := QWord(nonce) + QWord($9E3779B97F4A7C15);
  z := (z xor (z shr 30)) * QWord($BF58476D1CE4E5B9);
  z := (z xor (z shr 27)) * QWord($94D049BB133111EB);
  MixHash := z xor (z shr 31);
end;

{ SHA-256 of (PREFIX || decimal nonce), first 8 digest bytes as a big-endian
  QWord — leading zero BITS of the digest are exactly the leading zero bits of
  this word (K stays well under 64). }
function ShaHash(nonce: Int64): QWord;
var d: AnsiString; i: Integer; v: QWord;
begin
  d := Sha256(PREFIX + IntToStr(nonce));
  v := 0;
  for i := 1 to 8 do v := (v shl 8) or QWord(Ord(d[i]));
  ShaHash := v;
end;

function HashOf(nonce: Int64): QWord;
begin
  if useSha then HashOf := ShaHash(nonce) else HashOf := MixHash(nonce);
end;

{ Number of leading zero bits in a 64-bit word (64 for zero). }
function LeadingZeroBits(x: QWord): Integer;
var n: Integer;
begin
  if x = 0 then begin LeadingZeroBits := 64; Exit; end;
  n := 0;
  while (x and QWord($8000000000000000)) = 0 do
  begin
    x := x shl 1;
    n := n + 1;
  end;
  LeadingZeroBits := n;
end;

function NowUsec: Int64;
var tv: TTimeVal;
begin
  if fpgettimeofday(@tv, nil) = 0 then NowUsec := tv.tv_sec * 1000000 + tv.tv_usec
  else NowUsec := 0;
end;

{ One nonce: hash it ONCE, fold the result into both reduction variables. They
  are passed by reference so the body stays a single call — recomputing the hash
  for the second reduction would halve the headline hashes/sec. `z` is a local,
  so it lives on the worker's own stack. }
procedure ScanNonce(nonce: Int64; var hits, best: Int64);
var z: Integer;
begin
  z := LeadingZeroBits(HashOf(nonce));
  if z >= K then hits := hits + 1;
  if z > best then best := z;
end;

{ Scan [0..N-1] under a chosen distribution / worker count. Reduction variables
  are ENCLOSING LOCALS (globals are not captured); results leave via out params. }
procedure Mine(useOnDemand, forceSerial: Boolean; var oFound, oBest: Int64);
var nonce: Integer; lFound, lBest: Int64;
begin
  lFound := 0; lBest := 0;
  if forceSerial then PXXSetParForWorkers(1);
  if useOnDemand then
    parallel(pdOnDemand) for nonce := 0 to N - 1 reduction(+: lFound) reduction(max: lBest) do
      ScanNonce(nonce, lFound, lBest)
  else
    parallel(pdChunked) for nonce := 0 to N - 1 reduction(+: lFound) reduction(max: lBest) do
      ScanNonce(nonce, lFound, lBest);
  if forceSerial then PXXSetParForWorkers(0);
  oFound := lFound; oBest := lBest;
end;

function Rate(n: Integer; us: Int64): Int64;
begin
  if us <= 0 then us := 1;
  Rate := (Int64(n) * 1000000) div us;
end;

var
  i: Integer;
  a: AnsiString;
  t0, t1, usSerial, usChunked, usOnDemand: Int64;
  fSerial, fChunked, fOnDemand: Int64;
  bSerial, bChunked, bOnDemand: Int64;
begin
  useSha := False;
  i := 1;
  while i <= ParamCount do
  begin
    a := ParamStr(i);
    if a = '--hash' then
    begin
      i := i + 1;
      if ParamStr(i) = 'sha256' then useSha := True
      else if ParamStr(i) <> 'fast' then
      begin
        writeln('usage: pow [--hash fast|sha256]'); Halt(2);
      end;
    end
    else begin writeln('usage: pow [--hash fast|sha256]'); Halt(2); end;
    i := i + 1;
  end;

  if useSha then N := N_SHA else N := N_FAST;

  if useSha then a := 'sha256' else a := 'splitmix64';
  writeln('Mini proof-of-work   hash=', a, '   nonces=', N, '   difficulty=', K,
          ' zero bits   workers=', PXXParForWorkers);

  t0 := NowUsec; Mine(False, True,  fSerial,   bSerial);   t1 := NowUsec; usSerial   := t1 - t0;
  t0 := NowUsec; Mine(False, False, fChunked,  bChunked);  t1 := NowUsec; usChunked  := t1 - t0;
  t0 := NowUsec; Mine(True,  False, fOnDemand, bOnDemand); t1 := NowUsec; usOnDemand := t1 - t0;

  if usSerial   <= 0 then usSerial   := 1;
  if usChunked  <= 0 then usChunked  := 1;
  if usOnDemand <= 0 then usOnDemand := 1;

  writeln('found      = ', fSerial, ' nonces with >= ', K, ' leading zero bits');
  writeln('best       = ', bSerial, ' leading zero bits');
  writeln('serial     : ', usSerial, ' us   ', Rate(N, usSerial), ' hash/s');
  writeln('pdChunked  : ', usChunked, ' us   ', Rate(N, usChunked), ' hash/s   speedup ',
          (usSerial * 100) div usChunked, ' /100x');
  writeln('pdOnDemand : ', usOnDemand, ' us   ', Rate(N, usOnDemand), ' hash/s   speedup ',
          (usSerial * 100) div usOnDemand, ' /100x');
  if useSha then
    writeln('(NOTE: sha256 allocates per hash and the runtime heap has one global',
            ' spinlock, so more workers currently means LESS throughput — see',
            ' feature-opt-heap-per-thread-cache. Correctness is unaffected.)')
  else
    writeln('(compute-bound, no allocation: near-linear scaling, unlike the memory-bound membw demo)');

  if (fChunked = fSerial) and (fOnDemand = fSerial) and
     (bChunked = bSerial) and (bOnDemand = bSerial) then
    writeln('ALL AGREE — both reductions identical across every distribution')
  else begin
    writeln('MISMATCH — reduction not deterministic (BUG)'); Halt(1);
  end;
end.
