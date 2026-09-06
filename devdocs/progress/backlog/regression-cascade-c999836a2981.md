---
prio: 70
---

> **origin/master has advanced 3 commit(s) since this sha.** Re-verify at current HEAD before acting — the callback is tagged to the sha that was tested, which may no longer be the state of the tree.


# regression CASCADE: 36 jobs newly red in 85d70d700..c999836a2 (2 commits) — auto-filed by twatch

- **Type:** regression cascade (auto-filed by Track T watcher, host seven).
  Untriaged. 36 jobs went red in ONE sweep — treat as ONE root cause until
  triage proves otherwise; do NOT fan out per-job tickets.
- **Found:** 2026-09-06T05:59:55Z
- **Root-cause suspects in the red set:** none of the known root jobs (`fpc-bootstrap`, `selfhost-fixedpoint`). That is the ONLY heuristic applied here — it does not imply a harness event, and nothing in this filing looked at the build, the box or the range. See the Range section below for commits worth checking.

## Range
> **The named sha `c999836a2981` CANNOT be the cause** — it touches no buildable file (docs/tickets/tstate only). It is the sha that was TESTED, i.e. the upper bound of an untested range, and the cause is somewhere below it.

bad `c999836a2981`, last good `85d70d70076a`, **2 commit(s) in range** (2 of them buildable). **No idle bisect will happen** — the watcher skips cascades deliberately (one synthetic key matches no job), so this range is narrowed by hand or not at all.

**Buildable commits in the range, newest first:**
- `27dff0dd77fa` fix(p): a class property cannot be stored, which is the same rule as cannot be published
- `393fe018410b` fix(P): a `^T` whose T is never declared is refused, and tgeneric83/84/85 burn with it

## Repro (start with a suspect, or any listed job)
`tools/testmgr.py --tier native --job '<job>'` at c999836a298149d467ae79a19b13bafe71446e1b

(The sha above is the right one to REPRODUCE at — the jobs really are red
there — even when the Range section says it cannot be the CAUSE. Reproducing
and blaming are different questions and this line answers the first.)

## Newly red jobs
> Each job's own recorded failure REASON is printed under its name. **When the
> reasons and the Range section disagree, the reasons win.** The range is
> computed from what CHANGED, not from what the job can SEE — a missing guest
> loader, an absent dev package or a job that has never once passed on this box
> all produce a red that no commit in the range caused.

- `test-core#src:examples/tk/uses_tkinter_and_configparser.pas`
  - pascal26:344: error: forward type not resolved: `TPyRec` is used as the target of a `^` and is never declared as a type
- `test-core#src:test/test_criticalsection.pas`
  - pascal26:26: error: forward type not resolved: `TMutex` is used as the target of a `^` and is never declared as a type
- `test-core#src:test/test_fpc_compat_batch2.pas`
  - ok: $TMP [code=327448B data=34120B bss=85316B procs=851]
- `test-core#src:test/test_pyeval_bignum.pas`
  - pascal26:344: error: forward type not resolved: `TPyRec` is used as the target of a `^` and is never declared as a type
- `test-core#src:test/test_pyeval_compound.pas`
  - pascal26:344: error: forward type not resolved: `TPyRec` is used as the target of a `^` and is never declared as a type
- `test-core#src:test/test_pyeval_def.pas`
  - pascal26:344: error: forward type not resolved: `TPyRec` is used as the target of a `^` and is never declared as a type
- `test-core#src:test/test_pyeval_fstring.pas`
  - pascal26:344: error: forward type not resolved: `TPyRec` is used as the target of a `^` and is never declared as a type
- `test-core#src:test/test_pyeval_is_in.pas`
  - pascal26:344: error: forward type not resolved: `TPyRec` is used as the target of a `^` and is never declared as a type
- `test-core#src:test/test_pyeval_isinstance_del_dict.pas`
  - pascal26:344: error: forward type not resolved: `TPyRec` is used as the target of a `^` and is never declared as a type
- `test-core#src:test/test_pyeval_m1.pas`
  - pascal26:344: error: forward type not resolved: `TPyRec` is used as the target of a `^` and is never declared as a type
- `test-core#src:test/test_pyeval_m2.pas`
  - pascal26:344: error: forward type not resolved: `TPyRec` is used as the target of a `^` and is never declared as a type
- `test-core#src:test/test_pyeval_m3.pas`
  - pascal26:344: error: forward type not resolved: `TPyRec` is used as the target of a `^` and is never declared as a type
- `test-core#src:test/test_pyeval_memory_bytes.pas`
  - pascal26:344: error: forward type not resolved: `TPyRec` is used as the target of a `^` and is never declared as a type
- `test-core#src:test/test_pyeval_slice.pas`
  - pascal26:344: error: forward type not resolved: `TPyRec` is used as the target of a `^` and is never declared as a type
- `test-core#src:test/test_pyeval_trampoline_shapes.pas`
  - pascal26:344: error: forward type not resolved: `TPyRec` is used as the target of a `^` and is never declared as a type
- `test-core#src:test/test_setlen_in_parallel_for_body.pas`
  - pascal26:26: error: forward type not resolved: `TThreadHandle` is used as the target of a `^` and is never declared as a type
- `test-core#src:test/test_syncobjs.pas`
  - pascal26:26: error: forward type not resolved: `TMutex` is used as the target of a `^` and is never declared as a type
- `test-threads#src:test/test_async_parallel_compat.pas`
  - pascal26:26: error: forward type not resolved: `TThreadHandle` is used as the target of a `^` and is never declared as a type
- `test-threads#src:test/test_parallel_for.pas`
  - pascal26:26: error: forward type not resolved: `TThreadHandle` is used as the target of a `^` and is never declared as a type
- `test-threads#src:test/test_parallel_for_capture.pas`
  - pascal26:26: error: forward type not resolved: `TThreadHandle` is used as the target of a `^` and is never declared as a type
- `test-threads#src:test/test_parallel_for_capture_aggr.pas`
  - pascal26:26: error: forward type not resolved: `TThreadHandle` is used as the target of a `^` and is never declared as a type
- `test-threads#src:test/test_parallel_for_capture_callee.pas`
  - pascal26:26: error: forward type not resolved: `TThreadHandle` is used as the target of a `^` and is never declared as a type
- `test-threads#src:test/test_parallel_for_capture_scalar_types.pas`
  - pascal26:26: error: forward type not resolved: `TThreadHandle` is used as the target of a `^` and is never declared as a type
- `test-threads#src:test/test_parallel_for_capture_string.pas`
  - pascal26:26: error: forward type not resolved: `TThreadHandle` is used as the target of a `^` and is never declared as a type
- `test-threads#src:test/test_parallel_for_lang.pas`
  - pascal26:26: error: forward type not resolved: `TThreadHandle` is used as the target of a `^` and is never declared as a type
- `test-threads#src:test/test_parallel_for_nested_for_body.pas`
  - pascal26:26: error: forward type not resolved: `TThreadHandle` is used as the target of a `^` and is never declared as a type
- `test-threads#src:test/test_parallel_for_private.pas`
  - pascal26:26: error: forward type not resolved: `TThreadHandle` is used as the target of a `^` and is never declared as a type
- `test-threads#src:test/test_parallel_policy.pas`
  - pascal26:26: error: forward type not resolved: `TThreadHandle` is used as the target of a `^` and is never declared as a type
- `test-threads#src:test/test_parallel_policy_lang.pas`
  - pascal26:26: error: forward type not resolved: `TThreadHandle` is used as the target of a `^` and is never declared as a type
- `test-threads#src:test/test_parallel_policy_named.pas`
  - pascal26:26: error: forward type not resolved: `TThreadHandle` is used as the target of a `^` and is never declared as a type
- `test-threads#src:test/test_parallel_reduction.pas`
  - pascal26:26: error: forward type not resolved: `TThreadHandle` is used as the target of a `^` and is never declared as a type
- `test-threads#src:test/test_parallel_writeln_atomic.pas`
  - pascal26:26: error: forward type not resolved: `TThreadHandle` is used as the target of a `^` and is never declared as a type
- `test-threads#src:test/test_sched_reactor_exhaustion.pas`
  - pascal26:26: error: forward type not resolved: `TThreadHandle` is used as the target of a `^` and is never declared as a type
- `test-threads#src:test/test_sched_reactors_wide.pas`
  - pascal26:26: error: forward type not resolved: `TThreadHandle` is used as the target of a `^` and is never declared as a type
- `test-threads#src:test/test_threadsafe_refcount_lockfree.pas@1`
  - pascal26:26: error: forward type not resolved: `TThreadHandle` is used as the target of a `^` and is never declared as a type
- `test-threads#src:test/test_threadsafe_refcount_lockfree.pas@2`
  - pascal26:26: error: forward type not resolved: `TThreadHandle` is used as the target of a `^` and is never declared as a type

*Cascade stub: one signal for one event. Track T agent (face 2) or the owning
dev track triages the root; individual tickets only for whatever remains red
after the root is fixed.*
