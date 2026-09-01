program threadsafe_heap_scaling;
{ --threadsafe allocator scaling (feature-threadsafe-heap-optimize).

  The TOTAL amount of allocator work is held constant and split across the
  threads, so the shape of the answer is the whole point:

    * a perfectly scaling allocator keeps wall time FLAT as threads rise;
    * a single global lock makes it RISE, because the work serialises;
    * a badly-spinning lock makes it rise FASTER than serialisation alone,
      because waiters interfere with the holder they are waiting for.

  That third effect is the one this benchmark was written to expose, and it is
  what the test-and-test-and-set + PAUSE spin in EmitAcquireHeapLock removed.
  What remained after it was the honest serialisation of one global lock.

  THAT IS NOW FLAT, and the sentence that used to stand here -- "flattening THAT
  needs per-thread arenas, which need real thread-local storage the runtime does
  not have yet" -- was wrong in both halves by the time anyone acted on it. TLS
  landed 2026-08-20, and it is not ARENAS that was wanted: PXX_ALLOC_CENSUS on
  an equivalent GetMem/FreeMem-pair workload (frankB's allocscale, 2M pairs)
  reports bump=3 against 1955448 reuse, so privatising the arena would have
  moved three allocations out of two million. What it wanted
  was the size-class BINS, and those are now a per-thread magazine held in the
  TLS block, read by a fast path emitted at the two allocator call sites
  (HeapMagazineEnabled, ir_codegen.inc). Measured here, interleaved A/B,
  min of 3:

      threads          1     2     4     8
      global lock    28ms  53ms  65ms  80ms      (vs1x100: 100 182 224 258)
      magazine       15ms  20ms  10ms   5ms      (vs1x100: 100 131  62  31)

  THE SHAPE IS THE RESULT, not the 1.9x on the first column. The top row RISES
  with threads -- the serialisation this benchmark was built to show -- and the
  bottom row FALLS below 100, which means the constant total work is finally
  being done in parallel. The 2-thread row is thread startup rather than the
  allocator and dominates at that size in both rows.

  The magazine's pop and push are a locked `xchg` each, for a signal-safety
  reason argued at the emitter. That costs about half the single-thread win --
  the same column reads 9ms without them -- and is why it is 15 and not 9.

  -dPXX_NO_HEAP_MAG rebuilds this binary with the magazine off and reproduces
  the top row, which is how both rows above came from ONE source.

  Run: make benchmark-threadsafe-heap
  Numbers are noisy on a loaded box — compare RATIOS between rows, not the
  absolute milliseconds, and take a median of a few runs. }

uses palthread, palthreadobj, pxxcio;

const
  TOTAL = 400000;   { GetMem/FreeMem pairs, TOTAL — divided among the threads }
  SZ    = 128;

type
  TChurn = class(TThread)
  public
    Iters: Integer;
  protected
    procedure Execute; override;
  end;

procedure TChurn.Execute;
var
  j: Integer;
  p: Pointer;
begin
  for j := 1 to Iters do
  begin
    GetMem(p, SZ);
    FreeMem(p);
  end;
end;

var
  ths: array[0..15] of TChurn;
  nt, i: Integer;
  s0, n0, s1, n1: Int64;
  ms, baseMs: Int64;

begin
  baseMs := 0;
  nt := 1;
  while nt <= 8 do
  begin
    __pxx_clock_gettime(1, @s0, @n0);          { CLOCK_MONOTONIC }
    for i := 0 to nt - 1 do
    begin
      ths[i] := TChurn.Create(True);
      ths[i].Iters := TOTAL div nt;
      ths[i].Start;
    end;
    for i := 0 to nt - 1 do ths[i].WaitFor;
    __pxx_clock_gettime(1, @s1, @n1);
    ms := (s1 - s0) * 1000 + (n1 - n0) div 1000000;
    if nt = 1 then baseMs := ms;
    if baseMs = 0 then baseMs := 1;
    { x100 rather than a real, because the point is a ratio and this keeps the
      benchmark free of float formatting. 100 = flat = perfect scaling. }
    WriteLn('threads=', nt, ' ms=', ms, ' vs1x100=', (ms * 100) div baseMs);
    for i := 0 to nt - 1 do ths[i].Free;
    nt := nt * 2;
  end;
end.
