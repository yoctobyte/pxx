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
  What remains is the honest serialisation of one global lock; flattening THAT
  needs per-thread arenas, which need real thread-local storage the runtime
  does not have yet.

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
