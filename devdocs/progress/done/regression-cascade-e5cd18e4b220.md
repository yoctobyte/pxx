---
prio: 70
---

> **origin/master has advanced 4 commit(s) since this sha.** Re-verify at current HEAD before acting — the callback is tagged to the sha that was tested, which may no longer be the state of the tree.


# regression CASCADE: 13 jobs newly red in 6f085e162..e5cd18e4b (1 commits) — auto-filed by twatch

- **Type:** regression cascade (auto-filed by Track T watcher, host borg).
  Untriaged. 13 jobs went red in ONE sweep — treat as ONE root cause until
  triage proves otherwise; do NOT fan out per-job tickets.
- **Found:** 2026-09-13T14:57:05Z
- **Root-cause suspects in the red set:** none of the known root jobs (`fpc-bootstrap`, `selfhost-fixedpoint`). That is the ONLY heuristic applied here — it does not imply a harness event, and nothing in this filing looked at the build, the box or the range. See the Range section below for commits worth checking.

## Range
bad `e5cd18e4b220`, last good `6f085e16261e`, **1 commit(s) in range** (1 of them buildable). **No idle bisect will happen** — the watcher skips cascades deliberately (one synthetic key matches no job), so this range is narrowed by hand or not at all.

**Buildable commits in the range, newest first:**
- `e5cd18e4b220` fix(N): a dynamic receiver's attribute no longer binds to another class's offset

## Repro (start with a suspect, or any listed job)
`tools/testmgr.py --tier full --job '<job>'` at e5cd18e4b220306c1b9d1e3c9308371f7969a533

(The sha above is the right one to REPRODUCE at — the jobs really are red
there — even when the Range section says it cannot be the CAUSE. Reproducing
and blaming are different questions and this line answers the first.)

## Newly red jobs
> Each job's own recorded failure REASON is printed under its name. **When the
> reasons and the Range section disagree, the reasons win.** The range is
> computed from what CHANGED, not from what the job can SEE — a missing guest
> loader, an absent dev package or a job that has never once passed on this box
> all produce a red that no commit in the range caused.

- `test-uforth#src:tools/compiler_srchash.sh@1`
  - self-host fixedpoint: verified — 1 round(s), 60b34f9d4b31 (stamp read back; sources match it) | compiling uforth.py as Nil-Python ... | test-uforth: FAIL — uforth.py did not compile
- `test-uforth#src:tools/compiler_srchash.sh@10`
  - self-host fixedpoint: verified — 1 round(s), 60b34f9d4b31 (stamp read back; sources match it) | compiling uforth.py as Nil-Python ... | test-uforth: FAIL — uforth.py did not compile
- `test-uforth#src:tools/compiler_srchash.sh@11`
  - self-host fixedpoint: verified — 1 round(s), 60b34f9d4b31 (stamp read back; sources match it) | compiling uforth.py as Nil-Python ... | test-uforth: FAIL — uforth.py did not compile
- `test-uforth#src:tools/compiler_srchash.sh@12`
  - self-host fixedpoint: verified — 1 round(s), 60b34f9d4b31 (stamp read back; sources match it) | compiling uforth.py as Nil-Python ... | test-uforth: FAIL — uforth.py did not compile
- `test-uforth#src:tools/compiler_srchash.sh@13`
  - self-host fixedpoint: verified — 1 round(s), 60b34f9d4b31 (stamp read back; sources match it) | compiling uforth.py as Nil-Python ... | test-uforth: FAIL — uforth.py did not compile
- `test-uforth#src:tools/compiler_srchash.sh@2`
  - self-host fixedpoint: verified — 1 round(s), 60b34f9d4b31 (stamp read back; sources match it) | compiling uforth.py as Nil-Python ... | test-uforth: FAIL — uforth.py did not compile
- `test-uforth#src:tools/compiler_srchash.sh@3`
  - self-host fixedpoint: verified — 1 round(s), 60b34f9d4b31 (stamp read back; sources match it) | compiling uforth.py as Nil-Python ... | test-uforth: FAIL — uforth.py did not compile
- `test-uforth#src:tools/compiler_srchash.sh@4`
  - self-host fixedpoint: verified — 1 round(s), 60b34f9d4b31 (stamp read back; sources match it) | compiling uforth.py as Nil-Python ... | test-uforth: FAIL — uforth.py did not compile
- `test-uforth#src:tools/compiler_srchash.sh@5`
  - self-host fixedpoint: verified — 1 round(s), 60b34f9d4b31 (stamp read back; sources match it) | compiling uforth.py as Nil-Python ... | test-uforth: FAIL — uforth.py did not compile
- `test-uforth#src:tools/compiler_srchash.sh@6`
  - self-host fixedpoint: verified — 1 round(s), 60b34f9d4b31 (stamp read back; sources match it) | compiling uforth.py as Nil-Python ... | test-uforth: FAIL — uforth.py did not compile
- `test-uforth#src:tools/compiler_srchash.sh@7`
  - self-host fixedpoint: verified — 1 round(s), 60b34f9d4b31 (stamp read back; sources match it) | compiling uforth.py as Nil-Python ... | test-uforth: FAIL — uforth.py did not compile
- `test-uforth#src:tools/compiler_srchash.sh@8`
  - self-host fixedpoint: verified — 1 round(s), 60b34f9d4b31 (stamp read back; sources match it) | compiling uforth.py as Nil-Python ... | test-uforth: FAIL — uforth.py did not compile
- `test-uforth#src:tools/compiler_srchash.sh@9`
  - self-host fixedpoint: verified — 1 round(s), 60b34f9d4b31 (stamp read back; sources match it) | compiling uforth.py as Nil-Python ... | test-uforth: FAIL — uforth.py did not compile

*Cascade stub: one signal for one event. Track T agent (face 2) or the owning
dev track triages the root; individual tickets only for whatever remains red
after the root is fixed.*

## Log
- 2026-09-14 — auto-closed by the borg watcher: `cascade@e5cd18e4b220` passes at 4e3414d4d18e (tier full); it was red at e5cd18e4b220. Reopening is by a fresh NEW-RED stub, since a second red is a second finding with its own range.
