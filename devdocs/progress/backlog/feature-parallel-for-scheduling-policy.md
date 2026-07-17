---
prio: 55
track: A
---

# `parallel for` scheduling policy + reduction (load-aware, work-stealing)

- **Type:** feature — language surface (Track A/P: parser + IR) **and** runtime
  (Track B: RTL worker pool / OS-load sampler). File under A (touches shared
  `parser.inc`/IR); the RTL pool + samplers are the B sub-tasks.
- **Status (2026-07-17): CORE SHIPPED, reduction + Phase B + named-args remain.**
  - DONE — runtime (`lib/rtl/palparallel.pas`): `TParDist`/`TParWorkers`/
    `TParPolicy` + presets; `PXXParallelForP`; `pdChunked` (contiguous fan),
    `pdOnDemand`/`pdGuided` (atomic-counter work-stealing); `pwAllCores`/`pwFixed`/
    `pwLoadOnce`/`pwLoadCont`; `PXXQueryFreeCores` (/proc/stat, x86-64/i386/
    aarch64/arm32). Gate: `test_parallel_policy` (coverage exact, all modes).
  - DONE — language (`compiler/parser.inc`): `parallel(P) for` lowers to
    `PXXParallelForPP(@P)`; soft-keyword disambiguation vs a normal `parallel(x)`
    call; bare `parallel for` byte-identical (self-host fixedpoint). Gate:
    `test_parallel_policy_lang`.
  - DONE — **reduction** (`compiler/parser.inc`): `reduction(op: v)` between the
    range and `do`; private per-worker `__pfred0`, body refs redirected to it,
    combined under `PXXReduceLock`. Ops: `+ or xor` (identity 0, combine
    `v^ := v^ op __pfred0`) and `min max` (seed `__pfred0 := v^`, combine
    `if __pfred0 </> v^ then v^ := __pfred0`). Int64/Double/Integer/keyword types
    (the `__pfred0` decl emits the type-KEYWORD token, not a bare ident). `*`/`and`
    NOT offered — `(*` is the comment opener. Gate `test_parallel_reduction`;
    self-host byte-identical. Commits e78d1503 (+/or/xor), b7665f12 (min/max +
    keyword-type fix).
  - DONE — **named-arg clause** (`compiler/parser.inc`): `parallel(pdOnDemand,
    cap 90, chunk 64) for`, `parallel(workers pwLoadOnce, cap 80) for`,
    `parallel(n 3) for`. Named mode triggers when the first token is a key
    (dist/workers/cap/chunk/n) or a bare pd*/pw* enum; else the single-expr @P
    form. Const-folded to 5 ints → `PXXParallelForN` (scalars only, no record
    materialization); `n` implies pwFixed. Composes with reduction. Bare-enum arg
    now works too. Gate `test_parallel_policy_named`; self-host byte-identical.
    Commit efc654e0.
  - DONE — **multi-variable reduction** (`compiler/parser.inc`, MAX_REDVARS=8):
    `reduction(+: sum, count)` (comma-list, same op) and stacked
    `reduction(max: best) reduction(+: t)` (different ops). Per-entry model; the
    four synthesis spots iterate; one `PXXReduceLock` brackets all folds; a var in
    two reductions is rejected. Gate `test_parallel_reduction` (comma-list +
    mixed-op cases); self-host byte-identical. Commit 2a7b794c.
  - DONE — reduction **`and` + `mul`** (`compiler/parser.inc`, commit 0af32212):
    op set now `+ or xor and min max mul` (all associative/commutative monoids).
    `and` = token, type picks identity (all-ones `not 0` for ordinals, `True` for
    Boolean); `mul` = word (since `*` is `(*` the comment opener), combines with a
    real tkStar, identity 1. `/ div mod` stay rejected (not associative). Gate +
    cross via `test_parallel_reduction`.
  - DONE — **Phase B** mid-region dynamic `pwLoadCont` (`lib/rtl/palparallel.pas`,
    commit 62400486): a pool of all cores runs the steal loop, each worker gated on
    its index < ActiveTarget (parks on a futex over the limit); a monitor thread
    re-samples /proc/stat every ~50ms, updates ActiveTarget to the free-CPU
    headroom, and wakes parked workers. Result-invariant (atomic counter still
    covers each index once). Launcher wakes the monitor at region end (short region
    ~1-4ms, not the ~50ms tick). Gate `test_parallel_policy` (pwLoadOnce +
    pwLoadCont).
  - **FEATURE FUNCTIONALLY COMPLETE.** Remaining = optional refinements only:
    ramp/EMA smoothing of the load sample (monitor currently jumps to free-capped,
    could oscillate under many competing jobs); BSD `sysctl kern.cp_time` +
    cgroup `cpu.max`/`cpu.stat` samplers (Linux `/proc/stat` only today); reduction
    `*`/`and` — wait, those shipped (0af32212). Consider closing + filing the
    sampler refinements as a small separate ticket.
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
  TParFlag    = (pfPinThreads, pfNoStealFromMain, pfSpinWait);  { future modifiers }
  TParPolicy  = record
    dist:    TParDist;
    workers: TParWorkers;
    fixedN, capPct, minChunk: Integer;   { 0 = mode default }
    flags:   set of TParFlag;            { orthogonal boolean modifiers (later) }
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

Three ways to pass a policy, in ascending specificity — a preset, an inline
record, or **named args** in the clause (the compiler folds the named args into a
policy; preferred inline form, see rationale below):

```pascal
{ (a) preset — covers ~95% of uses, stays short }
parallel(ParPolite) for i := 0 to N-1 do Work(i);

{ (b) inline const record (plain record, compile-time const, NO heap) }
const HeavyIO: TParPolicy =
  (dist: pdOnDemand; workers: pwLoadCont; capPct: 80; minChunk: 64);
parallel(HeavyIO) for i := 0 to N-1 do Work(i);

{ (c) named args in the clause — inline tuning WITHOUT a named const, still
      type-checked + folded to a policy by the compiler (Phase 2 grammar) }
parallel(pdOnDemand, cap 90, chunk 64) for i := 0 to N-1 do Work(i);
parallel(workers pwLoadOnce, cap 90)   for i := 0 to N-1 do Work(i);

{ reduction: RTL gives each worker a private partial, combines at the barrier }
parallel(ParPolite) for i := 0 to N-1
  reduction(+: total)
do
  total := total + f(i);

{ default — all cores, chunked split, as today }
parallel for i := 0 to N-1 do Work(i);
```

Named-arg keys map 1:1 to `TParPolicy` fields (`dist`, `workers`, `cap`→capPct,
`chunk`→minChunk, `n`→fixedN); a bare `TParDist`/`TParWorkers`/preset as the first
arg sets that and defaults the rest. The parser validates keys + rejects
duplicate/contradictory axes — the safety a packed int can't give.

### Precedence
`loop clause` > `PXXSetParForPolicy(P)` (process default) > built-in default
(all cores, chunked).

## Why a RECORD (+ presets / named args), NOT packed bit-flags

Considered and rejected: encoding the policy as OR-able int constants
(`mLoadAware or 90`, `mNumCores or 8`). Reasons:

- **The axes are choose-ONE enums, not orthogonal toggles.** Distribution is
  `pdChunked` XOR `pdOnDemand` XOR `pdGuided`; OR/`+` implies a combinability that
  is meaningless (can't be chunked AND on-demand) and the compiler couldn't reject
  the nonsense.
- **Value-packing is single-payload + ambiguous.** One int carries one value, but
  a policy needs `capPct` AND `minChunk` AND maybe `fixedN`; sub-field bit
  allocation = hand-rolled bitfields = fragile. `X or 8` — cores? percent? chunk?
  unreadable.
- **`+` vs `or` is a live silent-miscompile.** `A + B <> A or B` the moment bits
  overlap or a payload overflows its field (carry corrupts the mode) — exactly the
  silent-wrong-value class this project keeps getting burned by.
- **The record has ~zero cost here.** A `const TParPolicy` is compile-time; the
  clause reads its fields at compile time (or passes a pointer to one static const,
  1 word) ONCE at region entry, never per iteration. The "record overhead" worry
  does not apply.
- **"Hard to OR-combine" is the point.** A policy is a fixed, validated
  combination; the type system SHOULD forbid soup. Presets give the ergonomic
  short form; the sensible run-modes are genuinely few.

**Where bit-flags DO belong (later):** genuinely orthogonal boolean MODIFIERS
(`pfPinThreads`, `pfNoStealFromMain`, `pfSpinWait`) → a `flags: set of TParFlag`
field. Pascal's `set of` gives OR ergonomics (`[pfPinThreads, pfSpinWait]`) WITH
type safety — never hand-OR'd ints. That is the modifier layer, not the axis layer.

## Names — OPEN sub-decision
Clear canonical names above; OpenMP name kept as a documented alias (NOT
`static`/`dynamic` as bare identifiers — both reserved dialect keywords). `pd`/`pw`
prefixes shown but not required — final spelling confirmed at implementation.
Passing a bare `TParDist` or `TParWorkers` = that axis set, the other defaulted.

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
  reduction(+:x)` — the direct model for the clause + reduction. `pwLoadOnce`/
  `pwLoadCont` are a worker-count policy OpenMP lacks (it has num_threads but no
  system-headroom throttle).
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
- 2026-07-17 (impl-red) — reduction(op:v) SHIPPED (+ or xor, Int64+Double);
  private __pfred0 combined under PXXReduceLock. `*` blocked by `(*` comment.
  Commit e78d1503.
- 2026-07-17 (impl) — Increments 1 (runtime: PXXParallelForP + distributions +
  /proc/stat load sampler) and 2 (language: `parallel(P) for` -> PXXParallelForPP,
  soft-keyword disambiguation) SHIPPED green (self-host byte-identical, cross
  x86-64/i386/aarch64). Reduction, Phase B monitor thread, and the named-arg
  clause remain. Commits: runtime 49cd869e, language 0e896f9d.
- 2026-07-17 (rev2) — Encoding decided: **record + presets**, NOT packed OR-able
  int flags (rationale section — axes are choose-one enums, packing is
  single-payload/ambiguous, `+`vs`or` is a silent-miscompile risk, record is
  zero-cost). Added **named-arg clause** form `parallel(pdOnDemand, cap 90, chunk
  64) for` as the preferred inline-tuning surface (Phase 2 grammar; compiler
  validates + folds to a policy). Future boolean modifiers → `flags: set of
  TParFlag`, never hand-OR'd ints.
