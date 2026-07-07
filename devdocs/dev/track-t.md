# Track T — offloaded continuous testing (watcher + agentic test manager)

Status: face 1 (watcher) landed 2026-07-07 (`feature-track-t-watcher`);
face 2 (agent) is backlog `feature-track-t-agent`. Design discussion +
decisions: user, 2026-07-07.

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
| `tools/testmgr.py` | adaptive parallel test runner (tiers quick/limited/full, resource-aware scheduling, calibrated timeouts, process-group kill). The gate itself. |
| `tools/twatch.py` | face 1: dumb, reliable watcher daemon. Fetch → debounce → run testmgr on new HEAD → publish sparse per-SHA reports. No AI. |
| `tools/twatch-setup.sh` | box readiness check (+ `--fetch-corpus`). Prints what's missing with apt hints and the start command. |
| `devdocs/progress/tstate/` | published state: `<host>.json` (rolling state), `reports/*.md` (only when something CHANGED or RED), `TSTATE.md` (index). |

## Deploy a watcher box (one-liner)

```sh
git clone git@github.com:yoctobyte/pxx.git ~/trackt \
  && ~/trackt/tools/twatch-setup.sh --fetch-corpus \
  && nohup ~/trackt/tools/twatch.py --clone ~/trackt >> ~/trackt.log 2>&1 &
```

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
