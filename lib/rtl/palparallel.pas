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

  { ---- scheduling policy (feature-parallel-for-scheduling-policy) ----
    Two ORTHOGONAL axes. `dist` = how iterations are split among the workers;
    `workers` = how many workers run. See the ticket for the full design. }
  TParDist = (
    pdChunked,    { contiguous even split, decided up front (OpenMP static) — cheapest, no coordination }
    pdGuided,     { on-demand with shrinking chunks (OpenMP guided) — cheap early, balanced tail }
    pdOnDemand);  { on-demand fixed chunks via an atomic counter (OpenMP dynamic) — best balance on uneven loads }
  TParWorkers = (
    pwAllCores,   { fixed = affinity core count (default) }
    pwFixed,      { exactly fixedN workers }
    pwLoadOnce,   { sample free CPU at region entry, cap to headroom (experimental) }
    pwLoadCont);  { like pwLoadOnce; mid-region re-sampling deferred (Phase B) — behaves as pwLoadOnce today }
  TParPolicy = record
    dist:     TParDist;
    workers:  TParWorkers;
    fixedN:   Integer;   { pwFixed worker count }
    capPct:   Integer;   { load cap %, 0 = default 90 (pwLoad*) }
    minChunk: Integer;   { on-demand/guided chunk floor, 0 = auto }
  end;

const
  { Hard ceiling on workers per parallel-for. Bounds the per-call thread/handle
    arrays below; well above any real core count we target. }
  PAR_MAX_WORKERS = 64;

  { Presets — cover the common combinations so simple calls stay short. }
  ParDefault:  TParPolicy = (dist: pdChunked;  workers: pwAllCores; fixedN: 0; capPct: 0;  minChunk: 0);
  ParBalanced: TParPolicy = (dist: pdOnDemand; workers: pwAllCores; fixedN: 0; capPct: 0;  minChunk: 0);
  ParPolite:   TParPolicy = (dist: pdOnDemand; workers: pwLoadOnce; fixedN: 0; capPct: 90; minChunk: 0);

{ Run body over every index in [lo..hi], fanned across up to PXXParForWorkers()
  threads, and return only after all chunks finish. An empty range (hi < lo) runs
  nothing. A single-element or tiny range runs inline on the caller with no
  spawn. Equivalent to PXXParallelForP(..., ParDefault). }
procedure PXXParallelFor(lo, hi: NativeInt; body: TParForBody; ctx: Pointer);

{ Policy-aware parallel-for. `pol` selects the distribution + worker count (see
  TParPolicy). This is what `parallel(P) for` lowers to. }
procedure PXXParallelForP(lo, hi: NativeInt; body: TParForBody; ctx: Pointer;
                          const pol: TParPolicy);

{ Estimate of currently-FREE logical CPUs from /proc/stat (idle fraction * cores),
  0 if unavailable (first call with no prior sample, or no /proc). Stateful:
  each call deltas against the previous call's snapshot. }
function PXXQueryFreeCores: Integer;

{ The worker count PXXParallelFor fans to: the process CPU affinity count
  (sched_getaffinity), clamped to [1..PAR_MAX_WORKERS], or a fixed fallback when
  the query fails. Cached after first call. Overridable with PXXSetParForWorkers
  (0 = re-query the CPU count). }
function PXXParForWorkers: Integer;
procedure PXXSetParForWorkers(n: Integer);

implementation

{ sched_getaffinity syscall number per arch (Linux). Anything without a number
  below falls through to the fixed-worker fallback. }
{ CPU-affinity worker autodetect via sched_getaffinity. QueryCpuCount fails SAFE:
  any r<=0 (incl. qemu-user's EINVAL) falls back to the fixed worker count, so
  enabling an arch only ever HELPS on real hardware and never breaks emulation.
  aarch64 was gated off on bug-a-parallel-for-aarch64-multi-capture (a BSS-align
  codegen bug that bus-errored the --threadsafe path); that is fixed (bssBase is
  now 8-aligned), so aarch64/arm32 are enabled here too. }
{$ifdef CPUX86_64}
const SYS_sched_getaffinity = 204;
{$define PXX_HAS_AFFINITY}
{$endif}
{$ifdef CPUI386}
const SYS_sched_getaffinity = 242;
{$define PXX_HAS_AFFINITY}
{$endif}
{$ifdef CPUAARCH64}
const SYS_sched_getaffinity = 122;
{$define PXX_HAS_AFFINITY}
{$endif}
{$ifdef CPU_ARM32}
const SYS_sched_getaffinity = 241;   { arm EABI }
{$define PXX_HAS_AFFINITY}
{$endif}

{ openat/read/close for /proc/stat load sampling (pwLoadOnce/pwLoadCont). Same
  fail-safe rule: no numbers or a read error → PXXQueryFreeCores returns 0 and the
  caller falls back to the fixed worker count. AT_FDCWD = -100, O_RDONLY = 0. }
{$ifdef CPUX86_64}
const SYS_openat = 257; SYS_read = 0; SYS_close = 3;
{$define PXX_HAS_PROCSTAT}
{$endif}
{$ifdef CPUI386}
const SYS_openat = 295; SYS_read = 3; SYS_close = 6;
{$define PXX_HAS_PROCSTAT}
{$endif}
{$ifdef CPUAARCH64}
const SYS_openat = 56; SYS_read = 63; SYS_close = 57;
{$define PXX_HAS_PROCSTAT}
{$endif}
{$ifdef CPU_ARM32}
const SYS_openat = 322; SYS_read = 3; SYS_close = 6;   { arm EABI }
{$define PXX_HAS_PROCSTAT}
{$endif}

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

{ ---- /proc/stat load sampler (pwLoadOnce/pwLoadCont) ---- }
{$ifdef PXX_HAS_PROCSTAT}
const
  PROC_STAT_PATH: array[0..10] of Char =
    ('/', 'p', 'r', 'o', 'c', '/', 's', 't', 'a', 't', #0);   { NUL-terminated }
var
  gLastIdle:  Int64 = 0;
  gLastTotal: Int64 = 0;

{ Parse the aggregate `cpu  u n s idle iowait ...` line. total = sum of all
  fields; idleAll = idle (field 3) + iowait (field 4). Returns False if the line
  is not the expected cpu-aggregate line. }
function ParseProcStat(var buf: array of Byte; n: Integer;
                       var idleAll, total: Int64): Boolean;
var i, fld: Integer; v: Int64; started: Boolean;
begin
  ParseProcStat := False;
  if (n < 4) or (buf[0] <> Ord('c')) or (buf[1] <> Ord('p'))
     or (buf[2] <> Ord('u')) or (buf[3] <> Ord(' ')) then Exit;
  i := 3; idleAll := 0; total := 0; fld := 0;
  while i < n do
  begin
    while (i < n) and (buf[i] = Ord(' ')) do Inc(i);
    if (i >= n) or (buf[i] = 10) then Break;      { end of line }
    v := 0; started := False;
    while (i < n) and (buf[i] >= Ord('0')) and (buf[i] <= Ord('9')) do
    begin v := v * 10 + (buf[i] - Ord('0')); Inc(i); started := True; end;
    if not started then Break;
    total := total + v;
    if (fld = 3) or (fld = 4) then idleAll := idleAll + v;
    Inc(fld);
  end;
  ParseProcStat := fld >= 5;
end;

function ReadProcStat(var idleAll, total: Int64): Boolean;
var fd, n, ig: NativeInt; buf: array[0..255] of Byte;
begin
  ReadProcStat := False;
  { openat(AT_FDCWD=-100, "/proc/stat", O_RDONLY=0) }
  fd := NativeInt(__pxxrawsyscall(SYS_openat, -100, NativeInt(@PROC_STAT_PATH[0]), 0, 0, 0, 0));
  if fd < 0 then Exit;
  n := NativeInt(__pxxrawsyscall(SYS_read, fd, NativeInt(@buf[0]), 256, 0, 0, 0));
  ig := NativeInt(__pxxrawsyscall(SYS_close, fd, 0, 0, 0, 0, 0));
  if ig = 0 then ;
  if n <= 0 then Exit;
  ReadProcStat := ParseProcStat(buf, Integer(n), idleAll, total);
end;

function PXXQueryFreeCores: Integer;
var idleNow, totalNow, dIdle, dTotal: Int64; cores: Int64;
begin
  PXXQueryFreeCores := 0;
  if not ReadProcStat(idleNow, totalNow) then Exit;
  if gLastTotal = 0 then
  begin
    gLastIdle := idleNow; gLastTotal := totalNow;   { first sample: no delta yet }
    Exit;                                           { 0 -> caller uses all cores }
  end;
  dIdle := idleNow - gLastIdle;
  dTotal := totalNow - gLastTotal;
  gLastIdle := idleNow; gLastTotal := totalNow;
  if dTotal <= 0 then Exit;
  if dIdle < 0 then dIdle := 0;
  cores := PXXParForWorkers;
  PXXQueryFreeCores := Integer((dIdle * cores) div dTotal);   { idleFrac * cores }
end;
{$else}
function PXXQueryFreeCores: Integer;
begin PXXQueryFreeCores := 0; end;   { no sampler on this target }
{$endif}

{ Resolve the worker count for a policy. Fail-safe: a missing/failed load sample
  yields all cores (still capped by capPct). }
function ResolveWorkers(const pol: TParPolicy): Integer;
var cores, cap, maxN, free, n: Integer;
begin
  cores := PXXParForWorkers;
  case pol.workers of
    pwFixed:
      begin n := pol.fixedN; if n < 1 then n := 1; end;
    pwLoadOnce, pwLoadCont:                         { pwLoadCont == pwLoadOnce for now }
      begin
        cap := pol.capPct; if cap <= 0 then cap := 90;
        maxN := (cores * cap) div 100; if maxN < 1 then maxN := 1;
        free := PXXQueryFreeCores;
        if free <= 0 then n := cores else n := free;
        if n > maxN then n := maxN;
      end;
  else
    n := cores;                                     { pwAllCores }
  end;
  if n < 1 then n := 1;
  if n > PAR_MAX_WORKERS then n := PAR_MAX_WORKERS;
  ResolveWorkers := n;
end;

{ palthread entry: unpack the range and dispatch into the body. }
procedure WorkerEntry(arg: Pointer);
var w: PWorkerArg;
begin
  w := PWorkerArg(arg);
  w^.Body(w^.Ctx, w^.Lo, w^.Hi);
end;

{ Contiguous even split across nw workers (OpenMP `static`). Chunk 0 stays on the
  calling thread; 1..nw-1 spawn; barrier-join. }
procedure ChunkedFan(lo, hi: NativeInt; body: TParForBody; ctx: Pointer; nw: NativeInt);
var
  total, i, chunk, rem, cur, cLo, cHi, spawned: NativeInt;
  args:    array[0..PAR_MAX_WORKERS-1] of TWorkerArg;
  handles: array[0..PAR_MAX_WORKERS-1] of TThreadHandle;
  ok:      array[0..PAR_MAX_WORKERS-1] of Boolean;
begin
  total := hi - lo + 1;
  if nw < 1 then nw := 1;
  if nw > total then nw := total;
  if nw = 1 then begin body(ctx, lo, hi); Exit; end;

  chunk := total div nw;
  rem   := total mod nw;
  cur := lo; spawned := 0;
  for i := 0 to nw - 1 do
  begin
    cLo := cur;
    cHi := cLo + chunk - 1;
    if i < rem then Inc(cHi);
    cur := cHi + 1;
    args[i].Body := body; args[i].Ctx := ctx; args[i].Lo := cLo; args[i].Hi := cHi;
    if i = 0 then
      ok[i] := False
    else
    begin
      ok[i] := PalThreadCreate(handles[i], @WorkerEntry, @args[i], 0) = 0;
      if ok[i] then Inc(spawned)
      else body(ctx, args[i].Lo, args[i].Hi);   { spawn failed: run inline }
    end;
  end;
  body(ctx, args[0].Lo, args[0].Hi);            { chunk 0 on this thread }
  for i := 1 to nw - 1 do
    if ok[i] then PalThreadJoin(handles[i]);
  if spawned = 0 then ;
end;

type
  { Shared descriptor for the on-demand / guided distribution. All workers hold a
    pointer to ONE of these (on the launching frame, outlives the join) and pull
    work by atomically bumping Counter. }
  PStealCtx = ^TStealCtx;
  TStealCtx = record
    Body:    TParForBody;
    Ctx:     Pointer;
    Counter: Integer;      { next unclaimed RELATIVE index 0..Total-1; 32-bit atomic }
    Lo:      NativeInt;    { absolute base for index translation }
    Total:   Integer;
    Chunk:   Integer;      { fixed grab size (pdOnDemand); guided floor }
    NW:      Integer;
    Guided:  Boolean;
  end;

{ Work-stealing worker: grab a chunk via an atomic fetch-add, run it, repeat until
  the range is drained. Each fetch-add reserves a disjoint [g,g+ch) — contiguous,
  no gaps/overlap — so coverage is exact regardless of chunk size (guided varies
  it). Guided reads Counter relaxed to size the next grab (a heuristic; the
  atomic add is what makes the reservation correct). }
procedure StealWorker(arg: Pointer);
var d: PStealCtx; g, ch, rem, e: Integer;
begin
  d := PStealCtx(arg);
  repeat
    if d^.Guided then
    begin
      rem := d^.Total - d^.Counter;
      if rem <= 0 then Break;
      ch := rem div d^.NW;
      if ch < d^.Chunk then ch := d^.Chunk;
    end
    else ch := d^.Chunk;
    g := Integer(__pxxatomic_add(@d^.Counter, ch));   { OLD value = my start }
    if g >= d^.Total then Break;
    e := g + ch - 1;
    if e >= d^.Total then e := d^.Total - 1;
    d^.Body(d^.Ctx, d^.Lo + g, d^.Lo + e);
  until False;
end;

procedure PXXParallelForP(lo, hi: NativeInt; body: TParForBody; ctx: Pointer;
                          const pol: TParPolicy);
var
  total, nw, i, ch, spawned: NativeInt;
  sc: TStealCtx;
  handles: array[0..PAR_MAX_WORKERS-1] of TThreadHandle;
  ok:      array[0..PAR_MAX_WORKERS-1] of Boolean;
begin
  if hi < lo then Exit;                          { empty range }
  total := hi - lo + 1;
  nw := ResolveWorkers(pol);
  if nw > total then nw := total;
  if nw < 1 then nw := 1;

  { pdChunked, the degenerate single-worker case, or a range too large for the
    32-bit atomic counter → the contiguous fan. }
  if (pol.dist = pdChunked) or (nw = 1) or (total > $7FFFFFFF) then
  begin
    ChunkedFan(lo, hi, body, ctx, nw);
    Exit;
  end;

  ch := pol.minChunk;
  if ch <= 0 then
  begin
    ch := total div (nw * 8);                     { auto: ~8 chunks per worker }
    if ch < 1 then ch := 1;
  end;
  sc.Body := body; sc.Ctx := ctx; sc.Counter := 0;
  sc.Lo := lo; sc.Total := Integer(total); sc.Chunk := Integer(ch);
  sc.NW := Integer(nw); sc.Guided := (pol.dist = pdGuided);

  spawned := 0;
  for i := 1 to nw - 1 do
  begin
    ok[i] := PalThreadCreate(handles[i], @StealWorker, @sc, 0) = 0;
    if ok[i] then Inc(spawned);
  end;
  StealWorker(@sc);                               { this thread is a worker too }
  for i := 1 to nw - 1 do
    if ok[i] then PalThreadJoin(handles[i]);
  if spawned = 0 then ;
end;

procedure PXXParallelFor(lo, hi: NativeInt; body: TParForBody; ctx: Pointer);
begin
  PXXParallelForP(lo, hi, body, ctx, ParDefault);
end;

end.
