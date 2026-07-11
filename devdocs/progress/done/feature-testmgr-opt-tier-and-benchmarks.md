---
prio: 60
---

# testmgr: opt-level differential tier + tracked benchmark runs

- **Type:** feature (testing infra) — **Track T**
- **Status:** done
- **Opened:** 2026-07-11 (user request, during the -O3 W1/W2 optimization
  campaign — see [[feature-opt-o3-register-pressure]])
- **Owner:** fable-trackt

## Why

The optimization campaign now ships passes at three tiers (-O0 reference,
-O2 default, -O3 experimental), and promotions move passes between them
(v194 -O2 flip, v196 W1-trio promotion). Two guarantees currently rest on
one-off manual runs by the dev agent:

1. **Semantic equivalence across O levels.** `make test-opt` covers ~21
   hand-picked programs; the promotion gate for v196 was a manual 564-program
   corpus sweep (`-O0` vs `-O2` compile+run+output-compare) in a scratch
   script. That sweep should be a standing, per-SHA, offloaded tier — it is
   exactly the cheap oracle that catches optimizer miscompiles, and exactly
   what T exists to offload. The pending -O3→-O2 promotion of the
   register-lifetime passes (r8-r13 scratch, loop/float residency) is blocked
   on soak evidence this tier would produce.
2. **Performance tracking.** Wins land with hyperfine numbers measured once,
   on the dev box, and are never re-checked — a silent perf REGRESSION (or a
   pass whose win evaporates after an unrelated change) goes unnoticed.
   Benchmarks also double as miscompile canaries (output checked before
   timing).

## What (two additions to `tools/testmgr.py`)

### 1. `--tier opt` — O-level differential sweep

- For every standalone-runnable `test/*.pas` (and the C corpus where it runs
  natively): compile at `-O0`, `-O2`, `-O3`; run each (timeout, stdin closed);
  compare stdout+exit code pairwise against `-O0`.
- Skip rules learned from the v196 promotion sweep (reuse/port the harness —
  it lived at scratchpad `diffgate.sh`, reproduced below):
  - test doesn't compile at -O0 or times out at -O0 → skip (not a diff);
  - KNOWN nondeterministic tests → skiplist: `test_c_gtk_*` (prints pointer
    values — nondeterministic even -O0 vs -O0), `lib_sockets` (fixed port,
    TIME_WAIT flakes across back-to-back runs). Keep the skiplist a visible
    file, not hardcode.
- Report per SHA into `tstate/` like other tiers: `opt: GREEN (pass=N skip=M)`
  or the diff list. A DIFF is a ticket-worthy regression (silent miscompile
  class — highest severity T can detect).
- Also fold in the self-host fixedpoints at each level (`-O2`/`-O3` build →
  rebuild → cmp), which `make test-opt` already models.

```bash
# v196 promotion harness (port me):
for t in test/*.pas; do
  CC "$t" d0 || skip; CC -O2 "$t" d2 || COMPILE-DIFF
  o0=$(timeout 10 ./d0 </dev/null 2>&1); r0=$?; [ $r0 -ge 124 ] && skip
  o2=$(timeout 10 ./d2 </dev/null 2>&1); r2=$?
  [ "$o0" != "$o2" ] || [ $r0 -ne $r2 ] && DIFF
done
```

### 2. `--bench` face — tracked benchmark timings per SHA

- Fixed suite, chosen to span the regimes the campaign identified
  (benchmarks/2026-07-11-o3-operand-scheduler.md):
  - `examples/mandelbrot/mandelbrot.pas --bench 400 300` — float compute
    (the xmm-residency showcase, 1.21× at -O3);
  - `examples/raytracer/raytracer.pas` — call-heavy float (1.09×);
  - `examples/primes/sieve.pas` — memory-bound int (control, ~1.0×);
  - compiler self-compile — the memory-bound big-program case (~1.05×).
- Each at `-O0`, `-O2`, `-O3`; verify OUTPUT equality across levels first
  (canary), then time (hyperfine if present, else N=5 min-of wall loop).
- Append per-SHA rows to `tstate/bench.tsv` (sha, date, workload, level,
  ms) — history stays greppable; the watcher publishes it like regression
  reports. Flag when a (workload, level) slows >10% vs the previous
  recorded SHA → file/refresh a regression ticket.
- Machine noise: pin to one box identity (tstate already carries host);
  compare only same-host rows.

## Gates / notes

- Track T owns `tools/testmgr.py` + report format — self-serve, no Track A
  sign-off needed. Gate = `tools/testmgr.py --tier full` still green + the
  new tier runs clean on current master (v196).
- Runtime budget: the 564-program sweep took ~3-4 min wall single-threaded;
  parallelize like existing tiers. Bench face ~2 min. Neither belongs in
  `quick`.
- Dev-loop consumers: Track O wants `opt` + `bench` results per pushed SHA
  to (a) gate the pending register-pass promotion on soak, (b) catch perf
  regressions from unrelated landings.

## Related

- [[feature-opt-o3-register-pressure]] — producer of the O-level surface;
  its log records the manual v196 promotion sweep this ticket automates.
- [[feature-optimization-levels]] — umbrella; `make test-opt` stays as the
  dev-loop quick gate, this tier is the offloaded broad version.
- [[project_track_t_concept]] — tstate/report conventions.

## Log
- 2026-07-11 — resolved, commit 597e4ab0.
