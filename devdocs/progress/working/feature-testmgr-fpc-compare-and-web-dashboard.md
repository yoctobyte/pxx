---
prio: 55
---

# testmgr: FPC benchmark comparison + static web dashboard (bench, suites, FPC conformance)

- **Type:** feature (testing infra) — **Track T**
- **Status:** working
- **Opened:** 2026-07-11 (user request)
- **Owner:** fable-trackt

## Why

The bench tier ([[feature-testmgr-opt-tier-and-benchmarks]]) tracks pxx timings
across -O0/-O2/-O3 per SHA, and the idle chain (full → opt → bench, once per SHA,
repo-idle) already runs it "when all other work is done, every so often." But:

1. **No external baseline.** Timings are pxx-vs-pxx. The user wants a
   **comparison against FPC** (3.2.2 on the box) — is our -O2/-O3 code competitive
   with the reference compiler? That's the meaningful number.
2. **Nothing is visible.** `twatch_web.py` shows live run + regressions + report
   links only. No bench history, no test-suite pass rates, no FPC-conformance
   breakdown. The user wants a **web page** for all of it, click-through, viewable
   without the daemon.
3. **FPC conformance is opaque.** `run_pascal_conformance.sh` prints pass/fail/
   skip/auto-gated counts to a log; `pxx.skip` has 237 freeform-reason entries.
   No structured output, no distinction between **"genuine gap"** and **"tests
   FPC internals we intentionally differ on — will never pass"**, no per-category
   view. FPC-suite burndown is deprioritized ([[task-pascal-conformance-long-tail]]
   prio 12) but the user still wants the RESULTS surfaced.

## What

Delivery decisions (user, 2026-07-11): **static committed HTML** (generated into
`tstate/`, viewable from git like BOARD.html, no daemon needed); **taxonomy built
now**, agentic per-test review of FPC tests deferred to a follow-up.

### 1. `--bench`: FPC comparison column
- For each runnable workload (mandelbrot/raytracer/sieve — NOT selfcompile),
  also compile with `fpc -O2` and time it. Append a `fpc` level row to
  `bench.tsv` (same schema). Canary = exit-code match vs pxx -O0 (stdout may
  differ in float formatting — don't gate on it). Skip silently if `fpc` absent.

### 2. `pxx.skip`: reason-tag taxonomy
- Reason field gains an optional leading tag: `wontfix:` (tests FPC internals /
  intentional divergence — never counts as failure), `gap:` (real unimplemented
  feature — open work). Untagged = **untriaged** (the current 237; agentic review
  promotes them). Runner stays backward-compatible (prints the whole reason).
- Category comes from the test-name prefix (existing `CATEGORIES` list).

### 3. `run_pascal_conformance.sh --json <path>`
- Emit structured summary: totals (pass/fail/skip/auto/untriaged/wontfix/gap) +
  per-test `{name, status, category, tag, reason}`. Consumed by the web build.

### 4. Static web dashboard (`tools/twatch_web.py --static --out <dir>`)
- `dashboard.html` — index: watcher status, own-test verdict, links out
  (bench.html, conformance.html, and the existing BOARD.html).
- `bench.html` — per-workload table, columns -O0/-O2/-O3/fpc, latest + history,
  slowdown flags.
- `conformance.html` — FPC suite: count breakdown, per-category table, full
  listing filterable by status/tag. Own-suite pass rate too.
- Self-contained (inline CSS, dark theme reused from the Flask PAGE), committed to
  `tstate/`. Flask app keeps serving live; static is the publish path.

### 5. Wire into twatch idle chain
- After the idle bench step (once per SHA), run conformance → `tstate/
  conformance.json`, then regenerate the static HTML into `tstate/`. All part of
  "extended test, when idle, every so often."

## Gates / notes
- Track T owns all of this (testmgr, twatch, report format, tstate, web) —
  self-serve. Gate = `tools/testmgr.py --tier full` green + the new paths run
  clean on current master. Test tooling with quick tiers + scratch, never long runs.

## Related
- [[feature-testmgr-opt-tier-and-benchmarks]] — the bench/opt tiers this extends.
- [[task-pascal-conformance-long-tail]] — the FPC gap burndown (deprioritized);
  this surfaces its state without committing to the burndown.
- Follow-up (to file): agentic per-test review of the ~237 untriaged FPC skips →
  fill `wontfix:`/`gap:` tags.

## Log
- 2026-07-11 — opened, building.
