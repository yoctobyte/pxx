{ SPDX-License-Identifier: Zlib }
unit palparallel;
{ M3 data-parallel loop runtime (meta-multithreading, feature-parallel-processing).

  The libc-free worker-pool backing the `parallel for` language surface. A single
  entry point:

      PXXParallelFor(lo, hi, body, ctx)

  partitions the inclusive index range [lo..hi] into contiguous chunks, runs each
  chunk on its own thread (one chunk stays on the calling thread — no idle
  spawn), and barrier-joins before returning. The loop body is a plain procedure
  with a fixed ABI:

      body(ctx, chunkLo, chunkHi)   { runs the iterations chunkLo..chunkHi }

  where `ctx` is an opaque pointer the caller uses to reach shared state (the
  parser synthesizes a captured-locals record and passes its address). The
  runtime never dereferences ctx — it only forwards it.

  Built entirely on the M1 PAL (palthread: clone/futex/mmap). No libc, no RTL
  thread manager. x86-64 first (the PAL it stands on is x86-64 today).

  THREAD-SAFETY: a body that allocates (managed strings, GetMem, objects) needs
  --threadsafe / {$threadsafe on} for the heap/ARC to lock — the `parallel for`
  surface enforces that at compile time, exactly like __pxxclone. A body that
  only reads shared state and writes disjoint indices is race-free by
  construction; overlapping writes to shared state are the user's responsibility
  (same contract as OpenMP `parallel for`). }

interface

uses palthread;

type
  { The loop-body ABI. ctx = opaque caller state; [lo..hi] = the inclusive
    sub-range this invocation must run. }
  TParForBody = procedure(ctx: Pointer; lo, hi: NativeInt);

const
  { Hard ceiling on workers per parallel-for. Bounds the per-call thread/handle
    arrays below; well above any real core count we target. }
  PAR_MAX_WORKERS = 64;

{ Run body over every index in [lo..hi], fanned across up to PXXParForWorkers()
  threads, and return only after all chunks finish. An empty range (hi < lo) runs
  nothing. A single-element or tiny range runs inline on the caller with no
  spawn. }
procedure PXXParallelFor(lo, hi: NativeInt; body: TParForBody; ctx: Pointer);

{ The worker count PXXParallelFor fans to: the process CPU affinity count
  (sched_getaffinity), clamped to [1..PAR_MAX_WORKERS], or a fixed fallback when
  the query fails. Cached after first call. Overridable with PXXSetParForWorkers
  (0 = re-query the CPU count). }
function PXXParForWorkers: Integer;
procedure PXXSetParForWorkers(n: Integer);

implementation

{ sched_getaffinity syscall number per arch (Linux). Anything without a number
  below falls through to the fixed-worker fallback. }
{ CPU-affinity worker autodetect. Enabled only where verified working (x86-64,
  i386 — real cpu counts). aarch64/arm32 keep the fixed-worker fallback: under
  qemu the syscall returns EINVAL (untestable) and aarch64 additionally trips the
  cross-codegen alignment bug (bug-a-parallel-for-aarch64-multi-capture) — their
  syscall numbers are recorded below, gate them on when real-hardware verified. }
{$ifdef CPUX86_64}
const SYS_sched_getaffinity = 204;
{$define PXX_HAS_AFFINITY}
{$endif}
{$ifdef CPUI386}
const SYS_sched_getaffinity = 242;
{$define PXX_HAS_AFFINITY}
{$endif}
{ aarch64 = 122 · arm EABI = 241 — recorded, not enabled (see note above). }

type
  { Per-worker argument: which sub-range to run plus the shared body+ctx. One
    lives per spawned thread for the duration of the parallel region (on the
    launching frame, which outlives the join). }
  PWorkerArg = ^TWorkerArg;
  TWorkerArg = record
    Body: TParForBody;
    Ctx:  Pointer;
    Lo:   NativeInt;
    Hi:   NativeInt;
  end;

var
  gWorkers: Integer = 0;   { 0 = not yet resolved }

function PopCount64(x: Int64): Integer;
var n: Integer;
begin
  n := 0;
  while x <> 0 do
  begin
    Inc(n, Integer(x and 1));
    x := (x shr 1) and $7FFFFFFFFFFFFFFF;   { logical shift: clear the sign bit }
  end;
  PopCount64 := n;
end;

{ Count the CPUs in this process's affinity mask. Returns 0 on any failure so the
  caller can fall back. }
function QueryCpuCount: Integer;
{$ifdef PXX_HAS_AFFINITY}
var
  mask: array[0..15] of Int64;   { 1024-bit cpuset — plenty }
  r, i, total: NativeInt;
begin
  for i := 0 to 15 do mask[i] := 0;
  { sched_getaffinity(pid=0, sizeof(mask), &mask) -> bytes written, or <0 errno }
  r := NativeInt(__pxxrawsyscall(SYS_sched_getaffinity, 0, 128, NativeInt(@mask[0]), 0, 0, 0));
  if r <= 0 then begin QueryCpuCount := 0; Exit; end;
  total := 0;
  { r = bytes filled; count set bits across the whole mask (extra words stay 0). }
  for i := 0 to 15 do Inc(total, PopCount64(mask[i]));
  QueryCpuCount := Integer(total);
end;
{$else}
begin
  QueryCpuCount := 0;   { arch without a syscall number -> fixed-worker fallback }
end;
{$endif}

function PXXParForWorkers: Integer;
var c: Integer;
begin
  if gWorkers = 0 then
  begin
    c := QueryCpuCount;
    if c < 1 then c := 4;                      { fallback when affinity query fails }
    if c > PAR_MAX_WORKERS then c := PAR_MAX_WORKERS;
    gWorkers := c;
  end;
  PXXParForWorkers := gWorkers;
end;

procedure PXXSetParForWorkers(n: Integer);
begin
  if n <= 0 then
    gWorkers := 0                              { 0 => re-query on next PXXParForWorkers }
  else
  begin
    if n > PAR_MAX_WORKERS then n := PAR_MAX_WORKERS;
    gWorkers := n;
  end;
end;

{ palthread entry: unpack the range and dispatch into the body. }
procedure WorkerEntry(arg: Pointer);
var w: PWorkerArg;
begin
  w := PWorkerArg(arg);
  w^.Body(w^.Ctx, w^.Lo, w^.Hi);
end;

procedure PXXParallelFor(lo, hi: NativeInt; body: TParForBody; ctx: Pointer);
var
  total, nw, i, chunk, rem, cur, cLo, cHi, spawned: NativeInt;
  args:    array[0..PAR_MAX_WORKERS-1] of TWorkerArg;
  handles: array[0..PAR_MAX_WORKERS-1] of TThreadHandle;
  ok:      array[0..PAR_MAX_WORKERS-1] of Boolean;
begin
  if hi < lo then Exit;                        { empty range }

  total := hi - lo + 1;
  nw := PXXParForWorkers;
  if nw < 1 then nw := 1;
  if nw > total then nw := total;              { never more workers than iterations }

  if nw = 1 then
  begin
    body(ctx, lo, hi);                         { degenerate: run inline, no spawn }
    Exit;
  end;

  { Even split with the remainder spread across the first `rem` chunks so every
    chunk differs by at most one iteration. }
  chunk := total div nw;
  rem   := total mod nw;

  cur := lo;
  spawned := 0;
  { Build each worker's range. Chunk 0 stays on THIS thread; chunks 1..nw-1 spawn. }
  for i := 0 to nw - 1 do
  begin
    cLo := cur;
    cHi := cLo + chunk - 1;
    if i < rem then Inc(cHi);                  { hand this chunk one of the leftovers }
    cur := cHi + 1;

    args[i].Body := body;
    args[i].Ctx  := ctx;
    args[i].Lo   := cLo;
    args[i].Hi   := cHi;

    if i = 0 then
      ok[i] := False                           { inline chunk — not a spawned thread }
    else
    begin
      ok[i] := PalThreadCreate(handles[i], @WorkerEntry, @args[i], 0) = 0;
      if ok[i] then Inc(spawned)
      else
        body(ctx, args[i].Lo, args[i].Hi);     { spawn failed: run it inline, still correct }
    end;
  end;

  { Run chunk 0 on the calling thread while the workers run. }
  body(ctx, args[0].Lo, args[0].Hi);

  { Barrier: join every thread that actually started. }
  for i := 1 to nw - 1 do
    if ok[i] then PalThreadJoin(handles[i]);

  if spawned = 0 then ;                         { silence unused in the all-inline path }
end;

end.
