---
prio: 70
---

> **origin/master has advanced 4 commit(s) since this sha.** Re-verify at current HEAD before acting — the callback is tagged to the sha that was tested, which may no longer be the state of the tree.


# regression CASCADE: 13 jobs newly red in 86a040124..379ba83c3 (6 commits) — auto-filed by twatch

- **Type:** regression cascade (auto-filed by Track T watcher, host borg).
  Untriaged. 13 jobs went red in ONE sweep — treat as ONE root cause until
  triage proves otherwise; do NOT fan out per-job tickets.
- **Found:** 2026-09-25T14:30:54Z
- **Root-cause suspects in the red set:** none of the known root jobs (`fpc-bootstrap`, `selfhost-fixedpoint`). That is the ONLY heuristic applied here — it does not imply a harness event, and nothing in this filing looked at the build, the box or the range. See the Range section below for commits worth checking.

## Range
> **The named sha `379ba83c32ec` CANNOT be the cause** — it touches no buildable file (docs/tickets/tstate only). It is the sha that was TESTED, i.e. the upper bound of an untested range, and the cause is somewhere below it.

bad `379ba83c32ec`, last good `86a040124be5`, **6 commit(s) in range** (6 of them buildable). **No idle bisect will happen** — the watcher skips cascades deliberately (one synthetic key matches no job), so this range is narrowed by hand or not at all.

**Buildable commits in the range, newest first:**
- `0536b2a57019` docs(D): micropython.md at pin v435 (13 of 16 drivers); census says "not installed"
- `7ea045145a76` feat(E,S): machine.time_pulse_us, bitstream, dht_readinto and _onewire on ESP; Pin.OPEN_DR
- `87c12d17b10e` chore(stable): pin v435 -- binary sha256 5d08cc804c4f
- `a457570295cc` fix(N): MicroPython driver walls 1-4 and `import utime as time`
- `e8bafa6c6511` test(E): grow the MicroPython driver census from 8 drivers to 16
- `4a4167bc6523` fix(nilpy): shifts, augmented bitwise, reflected bitwise and @ on a variant operand; set.a

## Repro (start with a suspect, or any listed job)
`tools/testmgr.py --tier full --job '<job>'` at 379ba83c32ec7e548ce87a05409cf1c6c7e9bc59

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
  - self-host fixedpoint: verified — 1 round(s), 5d08cc804c4f (stamp read back; sources match it) | compiling uforth.py as Nil-Python ... | test-uforth: FAIL — uforth.py did not compile
- `test-uforth#src:tools/compiler_srchash.sh@10`
  - self-host fixedpoint: verified — 1 round(s), 5d08cc804c4f (stamp read back; sources match it) | compiling uforth.py as Nil-Python ... | test-uforth: FAIL — uforth.py did not compile
- `test-uforth#src:tools/compiler_srchash.sh@11`
  - self-host fixedpoint: verified — 1 round(s), 5d08cc804c4f (stamp read back; sources match it) | compiling uforth.py as Nil-Python ... | test-uforth: FAIL — uforth.py did not compile
- `test-uforth#src:tools/compiler_srchash.sh@12`
  - self-host fixedpoint: verified — 1 round(s), 5d08cc804c4f (stamp read back; sources match it) | compiling uforth.py as Nil-Python ... | test-uforth: FAIL — uforth.py did not compile
- `test-uforth#src:tools/compiler_srchash.sh@13`
  - self-host fixedpoint: verified — 1 round(s), 5d08cc804c4f (stamp read back; sources match it) | compiling uforth.py as Nil-Python ... | test-uforth: FAIL — uforth.py did not compile
- `test-uforth#src:tools/compiler_srchash.sh@2`
  - self-host fixedpoint: verified — 1 round(s), 5d08cc804c4f (stamp read back; sources match it) | compiling uforth.py as Nil-Python ... | test-uforth: FAIL — uforth.py did not compile
- `test-uforth#src:tools/compiler_srchash.sh@3`
  - self-host fixedpoint: verified — 1 round(s), 5d08cc804c4f (stamp read back; sources match it) | compiling uforth.py as Nil-Python ... | test-uforth: FAIL — uforth.py did not compile
- `test-uforth#src:tools/compiler_srchash.sh@4`
  - self-host fixedpoint: verified — 1 round(s), 5d08cc804c4f (stamp read back; sources match it) | compiling uforth.py as Nil-Python ... | test-uforth: FAIL — uforth.py did not compile
- `test-uforth#src:tools/compiler_srchash.sh@5`
  - self-host fixedpoint: verified — 1 round(s), 5d08cc804c4f (stamp read back; sources match it) | compiling uforth.py as Nil-Python ... | test-uforth: FAIL — uforth.py did not compile
- `test-uforth#src:tools/compiler_srchash.sh@6`
  - self-host fixedpoint: verified — 1 round(s), 5d08cc804c4f (stamp read back; sources match it) | compiling uforth.py as Nil-Python ... | test-uforth: FAIL — uforth.py did not compile
- `test-uforth#src:tools/compiler_srchash.sh@7`
  - self-host fixedpoint: verified — 1 round(s), 5d08cc804c4f (stamp read back; sources match it) | compiling uforth.py as Nil-Python ... | test-uforth: FAIL — uforth.py did not compile
- `test-uforth#src:tools/compiler_srchash.sh@8`
  - self-host fixedpoint: verified — 1 round(s), 5d08cc804c4f (stamp read back; sources match it) | compiling uforth.py as Nil-Python ... | test-uforth: FAIL — uforth.py did not compile
- `test-uforth#src:tools/compiler_srchash.sh@9`
  - self-host fixedpoint: verified — 1 round(s), 5d08cc804c4f (stamp read back; sources match it) | compiling uforth.py as Nil-Python ... | test-uforth: FAIL — uforth.py did not compile

*Cascade stub: one signal for one event. Track T agent (face 2) or the owning
dev track triages the root; individual tickets only for whatever remains red
after the root is fixed.*
