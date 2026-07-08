# Track T — offloaded continuous testing (watcher + agentic test manager)

Status: face 1 (watcher) landed 2026-07-07 (`feature-track-t-watcher`);
face 2 (agent) live since 2026-07-07 (`feature-track-t-agent`, in working/).
One-stop launcher `./trackt` + two-phase watcher + learned-metrics scheduler
+ web UI landed 2026-07-08. Design discussion + decisions: user, 2026-07-07/08.

## Why

The full gate (all targets + corpus + conformance + self-host) costs 10+
serial minutes — too slow for a dev inner loop, yet a trivial change can
regress any target. Track T makes testing a PERMANENT BACKGROUND PROCESS:

- Dev tracks confirm **native** health themselves (seconds), push, move on.
- The full matrix runs asynchronously on whatever box is available.
- Regression feedback may arrive minutes later — that's accepted — but it is
  always tied to an **exact git SHA**, so diving back into the offending
  change is one checkout.

## The pieces

| tool | job |
|------|-----|
| `./trackt` (`tools/trackt.py`) | **the one-stop launcher**: status, daemon start/stop/restart, live progress view, manual runs, box setup + git-access check, config, log tail, web UI. Thin frontend over the state files below. |
| `tools/testmgr.py` | adaptive parallel test runner (tiers quick/native/limited/full). Learns per-job metrics on each box (`.testmgr/metrics.json`: duration/RSS/cores EWMA) and schedules by them: measured-mem packing, cores-sum cap, per-job hang timeouts (~10x expected), SLOW flags. Writes `.testmgr/live.json` progress each second (weighted % from expected durations). |
| `tools/twatch.py` | face 1: dumb, reliable watcher daemon. Two-phase: fast verdict at `fast_tier` (default `native`) minutes after a push; full matrix backfills while idle and is aborted+discarded when a testable push arrives. Skips docs/tstate-only commits. Publishes tstate; heartbeats `.testmgr/watch.json`; optional deterministic stub tickets (`autoticket`). |
| `tools/twatch-setup.sh` | box readiness check (+ `--fetch-corpus`). Prints what's missing with apt hints and the start command. |
| `tools/twatch_web.py` | optional read-only Flask UI (spawned by `trackt`): live run, history from `tstate/runs-<host>.ndjson`, regression frequency, report browser. Loopback-only by default. |
| `devdocs/progress/tstate/` | published state: `<host>.json` (rolling state), `runs-<host>.ndjson` (uncapped run archive), `reports/*.md` (only when something CHANGED or RED), `TSTATE.md` (index). |

Config lives in `<clone>/twatch.conf` (JSON; `trackt config` edits it —
tier/fast_tier/interval/debounce/no_bisect/autoticket/web/web_port;
interval/autoticket/no_bisect apply to a running daemon, the rest on restart).

## Deploy a watcher box

```sh
git clone git@github.com:yoctobyte/pxx.git ~/trackt-watch \
  && ~/trackt-watch/trackt setup --fetch-corpus \
  && ~/trackt-watch/trackt start
```
(`trackt setup` also verifies git fetch/push access. Equivalent low-level
one-liner lives in the `twatch-setup.sh` header.)

Notes:
- The box needs an ssh key with **write** access (the watcher pushes tstate).
- No FPC needed: the compiler self-seeds from the committed stable binary.
- Full tier wants `qemu-user` (i386/aarch64/arm/riscv32), `xvfb`, `gcc`;
  without qemu run `--tier limited`. Corpus trees are gitignored — fetch via
  `--fetch-corpus`, else those jobs SKIP (green).
- twatch **refuses a checkout with uncommitted changes** — it does detached
  checkouts of arbitrary SHAs and must never do that under a live dev tree.
  Always give it its own clone. (`--status` is read-only and works anywhere.)
- Several watcher hosts in parallel are fine: reports are host-tagged, pushes
  rebase-retry. testmgr's adaptive scheduler self-tunes to the box, so the
  same command fits a laptop or a Xeon.
- Knobs: `--tier`, `--host`, `--interval`, `--debounce` (repo-quiet window
  before testing a burst), `--once` (cron style), `--no-bisect`.

### Corpus trees: whose job
`library_candidates/` (lua/sqlite/zlib/c-testsuite/tcc/cjson) is gitignored;
absent trees make corpus jobs SKIP (reported green) — silent coverage loss.
- **Non-agentic watcher box:** MANUAL — the user runs
  `tools/install_lib_candidates.sh all` (or `twatch-setup.sh --fetch-corpus`)
  at deploy time and after new corpora land.
- **Agentic Track T:** the agent's duty. On each session it checks its
  watcher clones for missing corpus trees and runs
  `tools/install_lib_candidates.sh all` — SKIPped corpus jobs in tstate are a
  finding to fix, not a green to accept.

## Dev-track protocol ("confirm native, offload the matrix")

After a change (also in CLAUDE.md workflow norms):

1. Always confirm natively yourself: `tools/testmgr.py --tier quick` (+
   self-host fixedpoint for compiler changes). ~40s.
2. `tools/twatch.py --status` — is Track T covering the repo?
   - **exit 0 (UP):** push. Cross targets, corpus, breadth = T's job.
     Regressions come back asynchronously as tstate reports (and, with
     face 2, as tickets) naming your exact SHA.
   - **exit 1 (DOWN/absent):** old rules — run your lane's full gate
     (`--tier full`, or `limited` + the targets you touched) before pushing
     anything risky.
3. Master MAY carry cross-target reds for hours; tstate is the truth. A
   core-job red older than a day is a revert candidate.

### Liveness without pings
`--status` needs no network and no heartbeat: T counts as UP iff every
commit older than a grace window (default 45 min, `--grace`) was tested by
some host. A quiet watcher on a quiet repo is indistinguishable from a dead
one — and it doesn't matter, because there's nothing it should have tested.

## Report contract (sparse by design)

- All-green, nothing changed: only `<host>.json` + the `TSTATE.md` index
  move. One commit line: `tstate(host): <sha> GREEN`.
- Something changed or RED: additionally `reports/<utc>-<sha7>-<host>.md`
  with frontmatter (sha, parent_tested, host, tier, wall, scale, verdict)
  and NEW-RED / FIXED / STILL-RED lists, verbatim first-failure log, and a
  one-line repro (`testmgr --tier <t> --job '<name>'` at `<sha>`).
- Signal only, never log dumps. NEW-RED **vs the previously tested SHA** is
  the signal, not raw fail counts.
- Idle watcher time narrows open regression ranges: midpoint commit, failing
  job only (`testmgr --job`) — lazy bisect toward a single SHA.

## Face 2 — the Track T agent (backlog)

A Claude agent, supervised session or cron, that consumes tstate and adds
judgment: files/updates deduped regression tickets (one per failing-job
signature, repro + commit range), drives bisects instead of waiting for
idle, escalates day-old core reds with a revert proposal.

**Self-directed (user decision):** the T agent OWNS the Track T sources —
free to improve/refactor/optimize testmgr/twatch/report format/tiers on its
own initiative, no ticket or approval needed. Its gate: `testmgr --tier
full` green; and it tests the *tooling itself* with quick tiers against a
scratch bare repo (fake central), never with long runs. Watcher identity
writes only `tstate/**`; the agent identity may touch tickets like any
track agent — that's the deliberate difference between the faces.

## Testing the tooling (how face 1 was verified, repeatable)

```sh
S=/tmp/scratch; git clone --bare . $S/central.git          # fake central
tools/twatch.py --clone $S/wc --remote $S/central.git --tier quick --once
# break a test in a third clone, push, --once again -> RED report w/ exact SHA
# revert, --once again -> FIXED, regression closed
```
Quick tier only (~4s a run); never validate infra with full-tier runs.
