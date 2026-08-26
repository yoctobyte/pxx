---
summary: "META: development is wait-limited, not token-limited. Dev tracks stop running suites; T owns breadth and its report LATENCY becomes the product. Coordinates the tooling tickets that get us there."
type: meta
track: T
prio: 30
---

# META: dev throughput — Track A+* / Track T integration

- **Type:** meta / epic (dev environment, not the compiler) — **Track T**
- **Opened:** 2026-08-01.
- **Umbrella only.** Holds the goal, the measurements and the decisions. The
  work lives in the linked tickets; this one is closed when they are.

## The observation that started it

**We are not token-limited, we are wait-limited.** Weekly token budget goes
unspent because agents sit on test runs. Two 554s `gate.sh quick` runs in a
single session on 2026-08-01, both GREEN, both finding nothing — roughly 20
minutes of an agent doing nothing, twice, for zero information.

Meanwhile the watcher box (12-core xeon) is otherwise idle.

## Why "Track M" is NOT being created

The instinct to give this its own letter is right about the *kind* of work and
wrong about the *file lane*. CLAUDE.md's rule: a new **place code lives** → new
lane (rare, resisted); a new **kind of work** over existing files → tag. Dev
tooling is `tools/**` + `tstate/**` — that is Track T's file lane already, and
T's charter is literally "Tools & Testing", explicitly "a tool used for testing,
not regression testing only". So this is Track T with a `meta-` slug (the same
convention as `meta-dialect-extensions-and-fpc-strict`). No new letter.

## Measured 2026-08-01 (dev box, idle)

| step | time |
| --- | --- |
| one self-compile | **5.74 s** |
| `make compiler/pascal26` = build + byte-identical verify | **~12 s** |
| `testmgr --tier quick` (= the `test-quick` target) | **2–14 s** |
| `make test-nilpy` | **554 s** |
| `gate.sh quick` (quick + selfhost + **test-nilpy**) | **~650 s** |

Two facts that fall out and correct earlier assumptions:

1. **The build IS the self-host fixedpoint.** The `$(COMPILER)` rule compiles
   twice, `cmp`s byte-identical, and refuses to install without convergence
   (fails after 4 rounds). You cannot skip it and you should not want to — it
   costs ~6s, and it means *a compiler that cannot reproduce itself never leaves
   the working tree*. The scariest failure mode of "never test locally" is
   already self-detecting.
2. **`testmgr --tier quick` is already the fast canary** — 2–14s of dense
   torture tests. The 554s is `gate.sh` adding `test-nilpy` on top, not anything
   slow about the quick tier.

## The model

- **Dev loop (A, P, C, N, …):** `make compiler/pascal26` (~12s) → run the repro
  → push. No suites. Ever.
- **`gate.sh` is the PIN gate**, not the dev loop. CLAUDE.md's *"Run the gate
  with `tools/gate.sh` (quick | lib | full | check), and background THAT"* reads
  as the everyday instruction and is what pulled an agent into those two 554s
  runs. That line needs fixing.
- **Track T owns breadth.** Its **report latency is now the product** — at a 12s
  dev cycle, a late report costs *commits to unwind*, not minutes.
- **The one brake that stays: `pin`.** A red master is cheap and recoverable; a
  bad pin silently poisons Track B's ground for hours. Push freely, pin
  deliberately.
- **Accepted cost:** occasional regression avalanches. The accounting still
  wins — one T-side bisect (T already bisects on idle) against 10 × 554s of
  agent time — and the catastrophic case is fenced off by fact (1) above.

## Work items

- [[feature-t-publish-selfhost-red-immediately]] (75) — twatch publishes per
  TIER; the one red that invalidates everyone waits behind a whole tier.
- [[feature-t-agent-side-tstate-watch]] (65) — the missing return path. The
  offload only pays if findings arrive while the context that caused them is
  warm.
- [[feature-t-quick-canary-for-nilpy-and-c]] (70) — the canary exists for
  Pascal only.
- [[feature-t-testmgr-owns-pinning-interruptible]] (60) — pinning scheduled and
  interruptible.
- [[feature-t-quick-gate-must-be-quick-and-gate-lines-must-not-name-long-suites]]
  (60) — corrected in place; the surviving half is the DOC fix (gate.sh's role,
  and ticket `Gate:` lines).
- [[decide-gate-line-convention]] (U, 60) — the Track U half: what a ticket's
  `Gate:` line should require. Blocks nothing else here.
- [[feature-t-bench-idle-must-be-preemptible]] (55) — filed 2026-08-02: the one
  idle phase a new push cannot interrupt, and at ~2-3 min it is the largest
  number in the time-to-verdict path.
- [[decide-t-notification-transport-poll-not-webhooks]] (U, decided 2026-08-02)
  — the return path is a poll, permanently; and the daemon's loop is work-gated,
  so it must NOT grow a time-based backoff.
- Multi-box / core utilisation: `hard_cap = --jobs or nproc*2`, adaptive, and
  `xeon.json` sets no `max_cores` — so the xeon *should* already be using the
  box. **Verify from the `jobs=N cap=N scale=N` header testmgr prints in its own
  reports before tuning anything**; do not "fix" a config that is not broken.

## Status 2026-08-02

Five of the six original work items are closed: `publish-selfhost-red-immediately`,
`agent-side-tstate-watch` (shipped as `twatch --follow`), `quick-canary-for-nilpy-and-c`,
`quick-gate-must-be-quick…` and `decide-gate-line-convention`. **Open: pinning
(60), bench preemption (55), and the unticketed core-utilisation check in the
bullet above** — which is a *verification*, not a change: read testmgr's own
`jobs=N cap=N scale=N` header from a report before touching any config.

## Done when

An agent can land a compiler fix in ~15s of local work, and hears about any
regression it caused within minutes, without ever running a suite by hand.

## Measured 2026-08-03 — the claim, tested

User observation that prompted this: *"as far as I observe track T works as
intended, no new issues. Track A and T align well... maybe numbers can prove
it."* They do. Rerun any time with `tools/tstate_stats.py` — the point of
writing it down is that the claim stays falsifiable.

418 runs on xeon, 2026-07-31 .. 2026-08-03:

| | median | p90 | max |
|---|---|---|---|
| **commit -> first verdict** | **2.8 min** | 3.4 min | 7.5 min |
| commit -> full-tier verdict | 8.8 min | 10.2 min | 12.5 min |
| commit -> opt verdict | 12.7 min | 15.9 min | 17.2 min |
| full-tier run wall | 5.8 min | 6.6 min | 9.6 min |
| native run wall | 1.8 min | 1.9 min | 5.2 min |

**"Done when: ... hears about any regression it caused within minutes" — met.**
The first verdict on a sha lands in under 4 minutes nine times out of ten, and
never took more than 7.5 in this window.

**A/T alignment, quantified.** The watcher's auto-filed regression tickets:
**80 fixed, 7 rejected, 2 still open — 92% of resolved ones were real bugs.**
That is the number behind "they align well": T is not spending other agents'
triage cycles on noise. (Two of those 7 rejections were the enrollment cascade
and its stale seed, both of which now have guards —
[[task-t-suppress-autoticket-until-host-baselined]],
[[task-t-seed-from-stable-defeats-rebuild]] — so the ratio should improve, not
merely hold.) Only 6% of runs report NEW-RED at all, so the steady state is
quiet, which is what "no new issues" looks like from the other side.

**Core utilisation — the unticketed work item above, now VERIFIED, not tuned.**
testmgr's own header on this box reads `tier=full jobs=2040 cap=24 scale=1.00`.
`cap=24` is `nproc*2` on the 12-core xeon, and `scale=1.00` says calibration
finds the box at reference speed. Nothing is misconfigured; per the item's own
instruction, nothing was touched.

**One assumption corrected.** The full tier is **5.8 min median**, not the
"~45 min" that [[feature-twatch-full-tier-coverage-age]] was written against
(that figure came from the older box). It covers 42% of tested shas with a
median 25.8 min gap — but the max gap was 7.8h, so preemption starvation is
rarer than assumed and still real.

## Status 2026-08-03

Open: [[feature-t-testmgr-owns-pinning-interruptible]] (60) and
[[feature-t-bench-idle-must-be-preemptible]] (55). Both carry their own
priority and neither is blocked on this ticket.

**Prio 80 -> 40.** The urgency this was rated for was the *wait-limited*
premise — agents burning 20 minutes on 554s gate runs that found nothing. That
premise is measurably gone: the dev loop is the ~12s build, breadth is
offloaded, and the report comes back in under 3 minutes. The umbrella stays
open until its two remaining children land (its own rule), but it should not
head the ready queue while doing so — an 80 here also propagates down its
dependency edges and inflates everything it links.
