---
summary: "META: development is wait-limited, not token-limited. Dev tracks stop running suites; T owns breadth and its report LATENCY becomes the product. Coordinates the tooling tickets that get us there."
type: meta
track: T
prio: 80
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
- Multi-box / core utilisation: `hard_cap = --jobs or nproc*2`, adaptive, and
  `xeon.json` sets no `max_cores` — so the xeon *should* already be using the
  box. **Verify from the `jobs=N cap=N scale=N` header testmgr prints in its own
  reports before tuning anything**; do not "fix" a config that is not broken.

## Done when

An agent can land a compiler fix in ~15s of local work, and hears about any
regression it caused within minutes, without ever running a suite by hand.
