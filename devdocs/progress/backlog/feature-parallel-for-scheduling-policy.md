---
prio: 55
track: A
---

# `parallel for` scheduling policy + reduction (load-aware, work-stealing)

- **Type:** feature — language surface (Track A/P: parser + IR) **and** runtime
  (Track B: RTL worker pool / OS-load sampler). File under A (touches shared
  `parser.inc`/IR); the RTL pool + samplers are the B sub-tasks.
- **Opened:** 2026-07-17 (design agreed with user; implementation deferred —
  may want fresh context).
- **Builds on:** [[feature-parallel-processing]] (shipped `parallel for` + capture),
  [[meta-multithreading]]. Related runtime file: `lib/rtl/palparallel.pas`
  (`PXXParallelFor`, `PXXParForWorkers`, `sched_getaffinity` autodetect).

## Motivation

Today `parallel for` fans to a fixed worker count (CPU affinity) with a **static
contiguous split** and a join barrier. Two gaps:

1. **No work distribution choice.** Contiguous split is pathological for uneven
   workloads (Mandelbrot: in-set rows cluster in one worker → ~2x on 8 cores
   until you hand-interleave, see `examples/mandelbrot/mandelbrot_parallel.pas`).
   OpenMP solves this with `schedule(static|dynamic|guided)`; we have only static.
2. **No system-load awareness.** On a shared/busy box you want to consume only
   the FREE headroom (e.g. cap at ~90% total CPU, take half the free capacity per
   poll and re-check) instead of pinning every core. Useful mainly for LONG
   regions (sampling overhead is real) — an opt-in, experimental knob.

Plus a recurring safety gap: concurrent accumulation into a shared captured var
(`total := total + f(i)`) is a data race — parallel-for captures BY-REF, see
[[project_parallel_for_byref_capture_shared_write_race]] and `WriteCap`'s
1-worker guard. A first-class **reduction** makes the common case safe + ergonomic.

## Two ORTHOGONAL axes (design correction 2026-07-17)

An earlier draft mashed distribution and worker-count into one enum. They are
independent — OpenMP splits them into `schedule()` and `num_threads()` for the
same reason:

- **Distribution** — HOW to divide iterations among a fixed worker set (load
  balancing INSIDE the loop). Answers "which iterations go to which worker."
- **Workers** — HOW MANY workers to run (resource level vs the rest of the
  machine). Answers "how many, and when is that decided." Load-aware lives HERE,
  and does not care how the loop is split.

You compose them freely: "however many cores are free (load-aware) AND hand work
out on demand (dynamic) so those workers stay balanced."

### Axis 1 — distribution (the OpenMP `schedule` kinds)
| canonical (proposed) | OpenMP | meaning | overhead / balance |
| --- | --- | --- | --- |
| `pdChunked`  | static  | P contiguous blocks decided UP FRONT; zero runtime coordination. Bad on uneven loads (Mandelbrot). `static,chunk` variant = round-robin fixed chunks (interleave) | cheapest / worst |
| `pdGuided`   | guided  | on-demand, chunk size starts big and SHRINKS (∝ remaining/P): few grabs early (cheap), fine tail balance | middle / good |
| `pdOnDemand` | dynamic | persistent pool; a free worker grabs the next `minChunk` iters via an atomic next-index counter. Balances at runtime as workers free up | priciest / best |

Overhead↔balance ladder: `pdChunked` → `pdGuided` → `pdOnDemand` (small chunk).
`pdChunked` needs no pool (today's path); `pdGuided`/`pdOnDemand` need the Phase B
work-stealing pool + shared counter.

### Axis 2 — worker count (the `num_threads` / load axis)
| canonical (proposed) | meaning |
| --- | --- |
| `pwAllCores`  | fixed = affinity core count (today's default) |
| `pwFixed`     | explicit `fixedN` workers |
| `pwLoadOnce`  | sample free CPU at region ENTRY, pick P, run to completion (Phase A; cheap, no mid-region reaction) |
| `pwLoadCont`  | monitor thread re-samples every T ms, parks/wakes workers mid-region to hold the headroom target (Phase B; reacts to load changes, higher overhead) |

**Load-aware has two sub-modes (once vs continuous)** — they ARE `pwLoadOnce` /
`pwLoadCont`, and map directly onto build phases A / B.

### Policy record + presets
```pascal
type
  TParDist    = (pdChunked, pdGuided, pdOnDemand);
  TParWorkers = (pwAllCores, pwFixed, pwLoadOnce, pwLoadCont);
  TParPolicy  = record
    dist:    TParDist;
    workers: TParWorkers;
    fixedN, capPct, minChunk: Integer;   { 0 = mode default }
  end;
```
Convenience presets keep simple calls short:
```pascal
const
  ParAllCores: TParPolicy = (dist: pdChunked;  workers: pwAllCores);
  ParPolite:   TParPolicy = (dist: pdOnDemand; workers: pwLoadOnce; capPct: 90);
```

## Language surface (decided)

Optional policy value on the keyword — OpenMP's `schedule()`/`num_threads()`
promoted from a pragma to real syntax. Bare `parallel for` unchanged (default =
all cores, chunked), so existing code is untouched.

```pascal
{ preset }
parallel(ParPolite) for i := 0 to N-1 do Work(i);

{ tuned inline const record (plain record, compile-time const, NO heap) }
const HeavyIO: TParPolicy =
  (dist: pdOnDemand; workers: pwLoadCont; capPct: 80; minChunk: 64);
parallel(HeavyIO) for i := 0 to N-1 do Work(i);

{ reduction: RTL gives each worker a private partial, combines at the barrier }
parallel(ParPolite) for i := 0 to N-1
  reduction(+: total)
do
  total := total + f(i);

{ default — all cores, chunked split, as today }
parallel for i := 0 to N-1 do Work(i);
```

### Precedence
`loop clause` > `PXXSetParForPolicy(P)` (process default) > built-in default
(all cores, chunked).

## Names — OPEN sub-decision
Clear canonical names above; OpenMP name kept as a documented alias (NOT
`static`/`dynamic` as bare identifiers — both reserved dialect keywords). `pd`/`pw`
prefixes shown but not required — final spelling confirmed at implementation.
Passing a bare `TParDist` or `TParWorkers` = that axis set, the other defaulted.

## Runtime design — build order (A then B, decided)

### Phase A — region-entry load throttle (cheap, ~zero overhead)
`pwLoadOnce` at region entry only: compute `nw` from free CPU, run the existing
`pdChunked` split. No pool, no monitor thread.
- **Signal:** `/proc/stat` `cpu` line — `idleFrac = Δidle/Δtotal`,
  `freeCores = idleFrac*nCores`. One open/read/close (~5–20µs) via PAL file I/O.
  NOT `/proc/loadavg` (too laggy/coarse).
- **Zero-latency trick:** keep a module-global last snapshot `{idle,total,ts}`,
  refresh at each region entry, delta vs the PREVIOUS region (no two-sample sleep
  gap). First region (no prior) → all cores. Smooth back-to-back windows w/ an EMA.
- **Ramp / hysteresis (user's "50%→90%"):**
  `targetActive = min(nCores, activeNow + ceil(freeCores*0.5))`, hard cap
  `0.9*nCores` (configurable `capPct`). Converges without overshoot when multiple
  load-aware jobs ramp together.

### Phase B — dynamic work-stealing pool (`pdOnDemand`/`pdGuided` + `pwLoadCont`)
Two things land together (both need the persistent pool):
- **Distribution** `pdOnDemand`/`pdGuided`: workers grab `minChunk` iterations
  via an atomic next-index fetch-add (batch to amortize contention); `pdGuided`
  shrinks the chunk over time.
- **Worker count** `pwLoadCont`: a monitor thread samples `/proc/stat` every T ms
  and parks/wakes workers (futex) to hold the headroom target MID-region.

Costs: persistent pool, atomic contention, monitor thread, park/wake — worth it
only for long regions. This is what "saves the programmer from thread management"
(the MTProcs `ProcThreadPool` setup pain, but owned by the RTL). Note the axes are
independent: `pdOnDemand` + `pwAllCores` (balance, no throttle) and `pdChunked` +
`pwLoadOnce` (throttle, no rebalance) are both valid Phase-A/B mixes.

### Reduction (v1, decided)
`reduction(op: var[, var...])`, ops `+ * min max and or xor`. Lowering: each
worker gets a private zero/identity-init partial of `var`'s type; the barrier
folds partials with `op` into the real `var`. Needs: parser grammar
(`reduction(...)` after the header, before `do`), IR to carry the reduction list,
per-worker private slot allocation, a combine step at join. Start with scalar
ordinals/floats; managed types later.

## Portability

- Load sampler is backend-gated; the POLICY syntax always parses. Missing sampler
  → `pwLoadOnce`/`pwLoadCont` degrade to `pwAllCores`.
- Linux: `/proc/stat`. BSD: `sysctl kern.cp_time`. Windows: PDH/perf counters —
  likely skip (degrade). ESP/bare: no `/proc` → degrade. Non-issue per user.
- **cgroup-blind:** `/proc/stat` shows HOST cpus, ignores container CPU quota →
  over-parallelizes in a quota'd container. v1 = bare-Linux; later read
  `cpu.max`/`cpu.stat`. Document the limitation.

## Caveats to document

- **Memory-bound work is orthogonal** — more/fewer workers ≠ speed when
  memory-bound (self-compile is; see [[project_o3_w1_operand_scheduler]]). Don't
  sell load-aware as a universal speed knob.
- **Spawn cost:** short frequent regions pay thread create/join regardless →
  "recommended for long-running regions" is the honest label (esp. `pwLoadCont`).
- **SMT:** `/proc/stat` counts logical CPUs; 90% logical ≠ 90% useful. Heuristic.
- `pwLoadOnce`/`pwLoadCont` are EXPERIMENTAL/opt-in; `pdChunked` + `pwAllCores`
  stays the proven default.

## Precedent (for the implementer)

- **OpenMP** `#pragma omp parallel for schedule(static|dynamic|guided) num_threads(n)
  reduction(+:x)` — the direct model for the clause + reduction. `pmLoadAware` is a
  new schedule kind OpenMP lacks.
- **FPC `MTProcs`** (`ProcThreadPool.DoParallelLocalProc`) — library form; the
  global-pool setup is exactly the pain the RTL-owned pool removes.
- **Delphi PPL** `TParallel.For(..., APool)` — hands the loop a pool object;
  conceptual precedent for handing `parallel` a policy value.

## Acceptance

- Parser: `parallel(P) for` + `reduction(...)` parse; bare `parallel for`
  byte-identical to today (self-host unaffected).
- Phase A: `pwLoadOnce` throttles to headroom on a busy host (validate on
  `mandelbrot_parallel` under an artificial background load); ~zero overhead when
  idle. Falls back cleanly where no sampler.
- Phase B: `pdOnDemand` beats `pdChunked` on Mandelbrot (uneven load) without the
  hand-interleave; `pwLoadCont` holds the load target mid-region via the monitor
  thread.
- Reduction: `reduction(+: total)` gives the serial sum with N workers,
  deterministic for integer ops; gate + cross.
- Self-host byte-identical; cross green; land only green.

## Log
- 2026-07-17 — Design agreed: `parallel(P) for` syntax, A-then-B build order,
  reduction in v1. Implementation deferred (fresh context).
- 2026-07-17 (rev) — Split into TWO orthogonal axes (was one enum): **distribution**
  `TParDist` (pdChunked/pdGuided/pdOnDemand = OpenMP static/guided/dynamic) and
  **worker count** `TParWorkers` (pwAllCores/pwFixed/pwLoadOnce/pwLoadCont).
  Load-aware = axis 2, with once-vs-continuous sub-modes = `pwLoadOnce`
  (Phase A) / `pwLoadCont` (Phase B). Names still an open sub-decision.
