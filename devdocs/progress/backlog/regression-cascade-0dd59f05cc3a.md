---
prio: 70
---

> **origin/master has advanced 13 commit(s) since this sha.** Re-verify at current HEAD before acting — the callback is tagged to the sha that was tested, which may no longer be the state of the tree.


# regression CASCADE: 20 jobs newly red in 851f170cb..0dd59f05c (4 commits) — auto-filed by twatch

- **Type:** regression cascade (auto-filed by Track T watcher, host seven).
  Untriaged. 20 jobs went red in ONE sweep — treat as ONE root cause until
  triage proves otherwise; do NOT fan out per-job tickets.
- **Found:** 2026-09-06T15:16:57Z
- **Root-cause suspects in the red set:** none of the known root jobs (`fpc-bootstrap`, `selfhost-fixedpoint`). That is the ONLY heuristic applied here — it does not imply a harness event, and nothing in this filing looked at the build, the box or the range. See the Range section below for commits worth checking.

## Range
> **The named sha `0dd59f05cc3a` CANNOT be the cause** — it touches no buildable file (docs/tickets/tstate only). It is the sha that was TESTED, i.e. the upper bound of an untested range, and the cause is somewhere below it.

bad `0dd59f05cc3a`, last good `851f170cb454`, **4 commit(s) in range** (4 of them buildable). **No idle bisect will happen** — the watcher skips cascades deliberately (one synthetic key matches no job), so this range is narrowed by hand or not at all.

**Buildable commits in the range, newest first:**
- `99c416b54e7b` fix(P): FindSym ranked case-exactness above scope depth, and it is one walk now
- `9075fdcd3e61` fix(P): a class or record const is a constant when named through its type
- `b612f30e8fca` fix(P): a routine-local var array initializer was a missing fork, not a missing capability
- `962cd81e3610` fix(P): a record's static class method is reachable through an instance

## Repro (start with a suspect, or any listed job)
`tools/testmgr.py --tier full --job '<job>'` at 0dd59f05cc3a5187257914a4b9bfc6676f9378c7

(The sha above is the right one to REPRODUCE at — the jobs really are red
there — even when the Range section says it cannot be the CAUSE. Reproducing
and blaming are different questions and this line answers the first.)

## Newly red jobs
> Each job's own recorded failure REASON is printed under its name. **When the
> reasons and the Range section disagree, the reasons win.** The range is
> computed from what CHANGED, not from what the job can SEE — a missing guest
> loader, an absent dev package or a job that has never once passed on this box
> all produce a red that no commit in the range caused.

- `test-aarch64#src:test/test_parallel_for_private.pas`
  - ok: $TMP [code=458520B data=6344B bss=50788B procs=592]
- `test-aarch64#src:test/test_signal_sp_rewrite.pas`
  - +++ actual | @@ -1,3 +1 @@ | -caught, hits=1 | -raiser-ran-on-the-spare-stack=TRUE | -and execution continued | +
- `test-aarch64#src:test/test_stack_overflow_raise.pas`
  - --- expected | +++ actual | @@ -1,3 +1 @@ | recursing | -caught a stack overflow, hits=1 | -and execution continued, after=1000
- `test-arm32#src:test/test_parallel_for_private.pas`
  - ok: $TMP [code=515948B data=6392B bss=50708B procs=623]
- `test-arm32#src:test/test_signal_sp_rewrite.pas`
  - +++ actual | @@ -1,3 +1 @@ | -caught, hits=1 | -raiser-ran-on-the-spare-stack=TRUE | -and execution continued | +
- `test-arm32#src:test/test_stack_overflow_raise.pas`
  - --- expected | +++ actual | @@ -1,3 +1 @@ | recursing | -caught a stack overflow, hits=1 | -and execution continued, after=1000
- `test-c-conformance#shard3/6`
  - self-host fixedpoint: verified — 1 round(s), d2e4cff06df7 (stamp read back; sources match it) --shard 3/6 | FAIL 00040.c — exit code 1 (want 0) | test-c-conformance: 36 pass, 1 fail, 0 skip (of 37) |…
- `test-c-conformance-aarch64#shard3/6`
  - self-host fixedpoint: verified — 1 round(s), d2e4cff06df7 (stamp read back; sources match it) --shard 3/6 | FAIL 00040.c — exit code 1 (want 0) | test-c-conformance-aarch64: 36 pass, 1 fail, 0 skip (…
- `test-c-conformance-arm32#shard3/6`
  - self-host fixedpoint: verified — 1 round(s), d2e4cff06df7 (stamp read back; sources match it) --shard 3/6 | FAIL 00040.c — exit code 1 (want 0) | test-c-conformance-arm32: 36 pass, 1 fail, 0 skip (of…
- `test-c-conformance-i386#shard3/6`
  - self-host fixedpoint: verified — 1 round(s), d2e4cff06df7 (stamp read back; sources match it) --shard 3/6 | FAIL 00040.c — exit code 1 (want 0) | test-c-conformance-i386: 36 pass, 1 fail, 0 skip (of…
- `test-c-conformance-riscv32#shard3/6`
  - self-host fixedpoint: verified — 1 round(s), d2e4cff06df7 (stamp read back; sources match it) --shard 3/6 | FAIL 00040.c — exit code 1 (want 0) | test-c-conformance-riscv32: 36 pass, 1 fail, 0 skip (…
- `test-i386#src:test/test_parallel_for_private.pas`
  - ok: $TMP [code=266092B data=6344B bss=50708B procs=589]
- `test-i386#src:test/test_signal_sp_rewrite.pas`
  - +++ actual | @@ -1,3 +1 @@ | -caught, hits=1 | -raiser-ran-on-the-spare-stack=TRUE | -and execution continued | +
- `test-i386#src:test/test_stack_overflow_raise.pas`
  - --- expected | +++ actual | @@ -1,3 +1 @@ | recursing | -caught a stack overflow, hits=1 | -and execution continued, after=1000
- `test-lua#src:tools/compiler_srchash.sh`
  - @@ -1,4 +0,0 @@ | -HELLO, WORLD 12 Hello | -Hell0, W0rld | -brown,fox,quick,the | -9 8 5 3 2 1 | test-lua: FAILURES
- `test-lua-cross#src:tools/compiler_srchash.sh`
  - @@ -1,4 +0,0 @@ | -HELLO, WORLD 12 Hello | -Hell0, W0rld | -brown,fox,quick,the | -9 8 5 3 2 1 | test-lua-cross: FAILURES
- `test-riscv32#src:test/test_signal_sp_rewrite.pas`
  - Segmentation fault (core dumped) | +++ actual | @@ -1,3 +1 @@ | -caught, hits=1 | -raiser-ran-on-the-spare-stack=TRUE | -and execution continued | +
- `test-threads#src:test/test_threadsafe_heap_lock_deadlock_diag.pas`
  - Segmentation fault (core dumped) | expect_same: MISMATCH [test_ts_hl_diag26_exit] | --- expected | +++ actual | @@ -1 +1 @@ | -212 | +139
- `test-xtensa#src:test/test_signal_sp_rewrite.pas`
  - +++ actual | @@ -1,3 +1 @@ | -caught, hits=1 | -raiser-ran-on-the-spare-stack=TRUE | -and execution continued | +
- `test-xtensa#src:test/test_stack_overflow_raise.pas`
  - --- expected | +++ actual | @@ -1,3 +1 @@ | recursing | -caught a stack overflow, hits=1 | -and execution continued, after=1000

*Cascade stub: one signal for one event. Track T agent (face 2) or the owning
dev track triages the root; individual tickets only for whatever remains red
after the root is fixed.*
