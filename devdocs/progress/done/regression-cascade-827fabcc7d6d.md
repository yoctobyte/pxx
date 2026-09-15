---
prio: 70
---

> **origin/master has advanced 5 commit(s) since this sha.** Re-verify at current HEAD before acting — the callback is tagged to the sha that was tested, which may no longer be the state of the tree.


# regression CASCADE: 14 jobs newly red in f7a745e87..827fabcc7 (1 commits) — auto-filed by twatch

- **Type:** regression cascade (auto-filed by Track T watcher, host borg).
  Untriaged. 14 jobs went red in ONE sweep — treat as ONE root cause until
  triage proves otherwise; do NOT fan out per-job tickets.
- **Found:** 2026-09-15T06:00:43Z
- **Root-cause suspects in the red set:** none of the known root jobs (`fpc-bootstrap`, `selfhost-fixedpoint`). That is the ONLY heuristic applied here — it does not imply a harness event, and nothing in this filing looked at the build, the box or the range. See the Range section below for commits worth checking.

## Range
bad `827fabcc7d6d`, last good `f7a745e876ef`, **1 commit(s) in range** (1 of them buildable). **No idle bisect will happen** — the watcher skips cascades deliberately (one synthetic key matches no job), so this range is narrowed by hand or not at all.

**Buildable commits in the range, newest first:**
- `827fabcc7d6d` fix(N): a variant-carried METHOD result is moved, not retained -- the leak splits on the D

## Repro (start with a suspect, or any listed job)
`tools/testmgr.py --tier full --job '<job>'` at 827fabcc7d6d134590694d3560af498967c6c7f0

(The sha above is the right one to REPRODUCE at — the jobs really are red
there — even when the Range section says it cannot be the CAUSE. Reproducing
and blaming are different questions and this line answers the first.)

## Newly red jobs
> Each job's own recorded failure REASON is printed under its name. **When the
> reasons and the Range section disagree, the reasons win.** The range is
> computed from what CHANGED, not from what the job can SEE — a missing guest
> loader, an absent dev package or a job that has never once passed on this box
> all produce a red that no commit in the range caused.

- `test-threads#src:test/test_threadsafe_heap_lock_deadlock_diag.pas`
  - expect_same: MISMATCH [test_ts_hl_diag26_exit] | --- expected | +++ actual | @@ -1 +1 @@ | -212 | +124
- `test-uforth#src:tools/compiler_srchash.sh@1`
  - self-host fixedpoint: verified — 1 round(s), c304147cdebd (stamp read back; sources match it) | compiling uforth.py as Nil-Python ... | Segmentation fault | test-uforth: FAIL (exit 139) | timeout: th…
- `test-uforth#src:tools/compiler_srchash.sh@10`
  - self-host fixedpoint: verified — 1 round(s), c304147cdebd (stamp read back; sources match it) | compiling uforth.py as Nil-Python ... | Segmentation fault | test-uforth: FAIL (exit 139) | timeout: th…
- `test-uforth#src:tools/compiler_srchash.sh@11`
  - self-host fixedpoint: verified — 1 round(s), c304147cdebd (stamp read back; sources match it) | compiling uforth.py as Nil-Python ... | Segmentation fault | test-uforth: FAIL (exit 139) | timeout: th…
- `test-uforth#src:tools/compiler_srchash.sh@12`
  - self-host fixedpoint: verified — 1 round(s), c304147cdebd (stamp read back; sources match it) | compiling uforth.py as Nil-Python ... | Segmentation fault | test-uforth: FAIL (exit 139) | timeout: th…
- `test-uforth#src:tools/compiler_srchash.sh@13`
  - self-host fixedpoint: verified — 1 round(s), c304147cdebd (stamp read back; sources match it) | compiling uforth.py as Nil-Python ... | Segmentation fault | test-uforth: FAIL (exit 139) | timeout: th…
- `test-uforth#src:tools/compiler_srchash.sh@2`
  - self-host fixedpoint: verified — 1 round(s), c304147cdebd (stamp read back; sources match it) | compiling uforth.py as Nil-Python ... | Segmentation fault | test-uforth: FAIL (exit 139) | timeout: th…
- `test-uforth#src:tools/compiler_srchash.sh@3`
  - self-host fixedpoint: verified — 1 round(s), c304147cdebd (stamp read back; sources match it) | compiling uforth.py as Nil-Python ... | Segmentation fault | test-uforth: FAIL (exit 139) | timeout: th…
- `test-uforth#src:tools/compiler_srchash.sh@4`
  - self-host fixedpoint: verified — 1 round(s), c304147cdebd (stamp read back; sources match it) | compiling uforth.py as Nil-Python ... | Segmentation fault | test-uforth: FAIL (exit 139) | timeout: th…
- `test-uforth#src:tools/compiler_srchash.sh@5`
  - self-host fixedpoint: verified — 1 round(s), c304147cdebd (stamp read back; sources match it) | compiling uforth.py as Nil-Python ... | Segmentation fault | test-uforth: FAIL (exit 139) | timeout: th…
- `test-uforth#src:tools/compiler_srchash.sh@6`
  - self-host fixedpoint: verified — 1 round(s), c304147cdebd (stamp read back; sources match it) | compiling uforth.py as Nil-Python ... | Segmentation fault | test-uforth: FAIL (exit 139) | timeout: th…
- `test-uforth#src:tools/compiler_srchash.sh@7`
  - self-host fixedpoint: verified — 1 round(s), c304147cdebd (stamp read back; sources match it) | compiling uforth.py as Nil-Python ... | Segmentation fault | test-uforth: FAIL (exit 139) | timeout: th…
- `test-uforth#src:tools/compiler_srchash.sh@8`
  - self-host fixedpoint: verified — 1 round(s), c304147cdebd (stamp read back; sources match it) | compiling uforth.py as Nil-Python ... | Segmentation fault | test-uforth: FAIL (exit 139) | timeout: th…
- `test-uforth#src:tools/compiler_srchash.sh@9`
  - self-host fixedpoint: verified — 1 round(s), c304147cdebd (stamp read back; sources match it) | compiling uforth.py as Nil-Python ... | Segmentation fault | test-uforth: FAIL (exit 139) | timeout: th…

*Cascade stub: one signal for one event. Track T agent (face 2) or the owning
dev track triages the root; individual tickets only for whatever remains red
after the root is fixed.*

## Log
- 2026-09-15 — auto-closed by the borg watcher: `cascade@827fabcc7d6d` passes at bd35a383c7c2 (tier full); it was red at 827fabcc7d6d. Reopening is by a fresh NEW-RED stub, since a second red is a second finding with its own range.
