---
prio: 70
---

> **origin/master has advanced 12 commit(s) since this sha.** Re-verify at current HEAD before acting — the callback is tagged to the sha that was tested, which may no longer be the state of the tree.


# regression CASCADE: 42 jobs newly red in cab3205aa..562162b03 (6 commits) — auto-filed by twatch

- **Type:** regression cascade (auto-filed by Track T watcher, host seven).
  Untriaged. 42 jobs went red in ONE sweep — treat as ONE root cause until
  triage proves otherwise; do NOT fan out per-job tickets.
- **Found:** 2026-09-06T06:16:00Z
- **Root-cause suspects in the red set:** none of the known root jobs (`fpc-bootstrap`, `selfhost-fixedpoint`). That is the ONLY heuristic applied here — it does not imply a harness event, and nothing in this filing looked at the build, the box or the range. See the Range section below for commits worth checking.

## Range
> **The named sha `562162b03a02` CANNOT be the cause** — it touches no buildable file (docs/tickets/tstate only). It is the sha that was TESTED, i.e. the upper bound of an untested range, and the cause is somewhere below it.

bad `562162b03a02`, last good `cab3205aa9e5`, **6 commit(s) in range** (6 of them buildable). **No idle bisect will happen** — the watcher skips cascades deliberately (one synthetic key matches no job), so this range is narrowed by hand or not at all.

**Buildable commits in the range, newest first:**
- `be2c87890adc` feat(C): C on wasm32 reaches main — the C × wasm32 cell is no longer empty
- `27dff0dd77fa` fix(p): a class property cannot be stored, which is the same rule as cannot be published
- `393fe018410b` fix(P): a `^T` whose T is never declared is refused, and tgeneric83/84/85 burn with it
- `217e530a01d3` refactor(P): one postfix walker — the call-result loop was 231 lines of a weaker copy
- `7a49995024cd` bug(P): an open-array LITERAL loses its length through a procedural-type call
- `9799ae851868` fix(p): `default` is two clauses, and the split needed a refusal shipped with it

## Repro (start with a suspect, or any listed job)
`tools/testmgr.py --tier full --job '<job>'` at 562162b03a024d6b86f317333d97a5d0b616da2f

(The sha above is the right one to REPRODUCE at — the jobs really are red
there — even when the Range section says it cannot be the CAUSE. Reproducing
and blaming are different questions and this line answers the first.)

## Newly red jobs
> Each job's own recorded failure REASON is printed under its name. **When the
> reasons and the Range section disagree, the reasons win.** The range is
> computed from what CHANGED, not from what the job can SEE — a missing guest
> loader, an absent dev package or a job that has never once passed on this box
> all produce a red that no commit in the range caused.

- `test-aarch64#src:test/test_parallel_for_capture.pas`
  - pascal26:26: error: forward type not resolved: `TThreadHandle` is used as the target of a `^` and is never declared as a type
- `test-aarch64#src:test/test_parallel_for_capture_aggr.pas`
  - pascal26:26: error: forward type not resolved: `TThreadHandle` is used as the target of a `^` and is never declared as a type
- `test-aarch64#src:test/test_parallel_for_capture_string.pas`
  - pascal26:26: error: forward type not resolved: `TThreadHandle` is used as the target of a `^` and is never declared as a type
- `test-aarch64#src:test/test_parallel_for_lang.pas`
  - pascal26:26: error: forward type not resolved: `TThreadHandle` is used as the target of a `^` and is never declared as a type
- `test-aarch64#src:test/test_parallel_for_private.pas`
  - pascal26:26: error: forward type not resolved: `TThreadHandle` is used as the target of a `^` and is never declared as a type
- `test-aarch64#src:test/test_parallel_policy.pas`
  - pascal26:26: error: forward type not resolved: `TThreadHandle` is used as the target of a `^` and is never declared as a type
- `test-aarch64#src:test/test_parallel_policy_lang.pas`
  - pascal26:26: error: forward type not resolved: `TThreadHandle` is used as the target of a `^` and is never declared as a type
- `test-aarch64#src:test/test_parallel_policy_named.pas`
  - pascal26:26: error: forward type not resolved: `TThreadHandle` is used as the target of a `^` and is never declared as a type
- `test-aarch64#src:test/test_parallel_reduction.pas`
  - pascal26:26: error: forward type not resolved: `TThreadHandle` is used as the target of a `^` and is never declared as a type
- `test-aarch64#src:test/test_parallel_writeln_atomic.pas`
  - pascal26:26: error: forward type not resolved: `TThreadHandle` is used as the target of a `^` and is never declared as a type
- `test-arm32#src:test/test_parallel_for_capture_aggr.pas`
  - pascal26:26: error: forward type not resolved: `TThreadHandle` is used as the target of a `^` and is never declared as a type
- `test-arm32#src:test/test_parallel_for_capture_string.pas`
  - pascal26:26: error: forward type not resolved: `TThreadHandle` is used as the target of a `^` and is never declared as a type
- `test-arm32#src:test/test_parallel_for_lang.pas`
  - pascal26:26: error: forward type not resolved: `TThreadHandle` is used as the target of a `^` and is never declared as a type
- `test-arm32#src:test/test_parallel_for_private.pas`
  - pascal26:26: error: forward type not resolved: `TThreadHandle` is used as the target of a `^` and is never declared as a type
- `test-arm32#src:test/test_parallel_policy.pas`
  - pascal26:26: error: forward type not resolved: `TThreadHandle` is used as the target of a `^` and is never declared as a type
- `test-arm32#src:test/test_parallel_policy_lang.pas`
  - pascal26:26: error: forward type not resolved: `TThreadHandle` is used as the target of a `^` and is never declared as a type
- `test-arm32#src:test/test_parallel_policy_named.pas`
  - pascal26:26: error: forward type not resolved: `TThreadHandle` is used as the target of a `^` and is never declared as a type
- `test-arm32#src:test/test_parallel_reduction.pas`
  - pascal26:26: error: forward type not resolved: `TThreadHandle` is used as the target of a `^` and is never declared as a type
- `test-arm32#src:test/test_parallel_writeln_atomic.pas`
  - pascal26:26: error: forward type not resolved: `TThreadHandle` is used as the target of a `^` and is never declared as a type
- `test-fgl#src:tools/compiler_srchash.sh`
  - pascal26:987: note: TODO : fix inlining to work! InternalItems[Result]^ | pascal26:1124: note: TODO : fix inlining to work! InternalItems[Result]^ | pascal26:1248: note: TODO : fix inlining to work!…
- `test-i386#src:test/test_parallel_for_capture_aggr.pas`
  - pascal26:26: error: forward type not resolved: `TThreadHandle` is used as the target of a `^` and is never declared as a type
- `test-i386#src:test/test_parallel_for_capture_string.pas`
  - pascal26:26: error: forward type not resolved: `TThreadHandle` is used as the target of a `^` and is never declared as a type
- `test-i386#src:test/test_parallel_for_lang.pas`
  - pascal26:26: error: forward type not resolved: `TThreadHandle` is used as the target of a `^` and is never declared as a type
- `test-i386#src:test/test_parallel_for_private.pas`
  - pascal26:26: error: forward type not resolved: `TThreadHandle` is used as the target of a `^` and is never declared as a type
- `test-i386#src:test/test_parallel_policy.pas`
  - pascal26:26: error: forward type not resolved: `TThreadHandle` is used as the target of a `^` and is never declared as a type
- `test-i386#src:test/test_parallel_policy_lang.pas`
  - pascal26:26: error: forward type not resolved: `TThreadHandle` is used as the target of a `^` and is never declared as a type
- `test-i386#src:test/test_parallel_policy_named.pas`
  - pascal26:26: error: forward type not resolved: `TThreadHandle` is used as the target of a `^` and is never declared as a type
- `test-i386#src:test/test_parallel_reduction.pas`
  - pascal26:26: error: forward type not resolved: `TThreadHandle` is used as the target of a `^` and is never declared as a type
- `test-i386#src:test/test_parallel_writeln_atomic.pas`
  - pascal26:26: error: forward type not resolved: `TThreadHandle` is used as the target of a `^` and is never declared as a type
- `test-nilpy#src:examples/tk/uses_tkinter_and_configparser.pas`
  - pascal26:344: error: forward type not resolved: `TPyRec` is used as the target of a `^` and is never declared as a type
- `test-nilpy#src:test/test_pyeval_bignum.pas`
  - pascal26:344: error: forward type not resolved: `TPyRec` is used as the target of a `^` and is never declared as a type
- `test-nilpy#src:test/test_pyeval_compound.pas`
  - pascal26:344: error: forward type not resolved: `TPyRec` is used as the target of a `^` and is never declared as a type
- `test-nilpy#src:test/test_pyeval_def.pas`
  - pascal26:344: error: forward type not resolved: `TPyRec` is used as the target of a `^` and is never declared as a type
- `test-nilpy#src:test/test_pyeval_fstring.pas`
  - pascal26:344: error: forward type not resolved: `TPyRec` is used as the target of a `^` and is never declared as a type
- `test-nilpy#src:test/test_pyeval_is_in.pas`
  - pascal26:344: error: forward type not resolved: `TPyRec` is used as the target of a `^` and is never declared as a type
- `test-nilpy#src:test/test_pyeval_isinstance_del_dict.pas`
  - pascal26:344: error: forward type not resolved: `TPyRec` is used as the target of a `^` and is never declared as a type
- `test-nilpy#src:test/test_pyeval_m1.pas`
  - pascal26:344: error: forward type not resolved: `TPyRec` is used as the target of a `^` and is never declared as a type
- `test-nilpy#src:test/test_pyeval_m2.pas`
  - pascal26:344: error: forward type not resolved: `TPyRec` is used as the target of a `^` and is never declared as a type
- `test-nilpy#src:test/test_pyeval_m3.pas`
  - pascal26:344: error: forward type not resolved: `TPyRec` is used as the target of a `^` and is never declared as a type
- `test-nilpy#src:test/test_pyeval_memory_bytes.pas`
  - pascal26:344: error: forward type not resolved: `TPyRec` is used as the target of a `^` and is never declared as a type
- `test-nilpy#src:test/test_pyeval_slice.pas`
  - pascal26:344: error: forward type not resolved: `TPyRec` is used as the target of a `^` and is never declared as a type
- `test-nilpy#src:test/test_pyeval_trampoline_shapes.pas`
  - pascal26:344: error: forward type not resolved: `TPyRec` is used as the target of a `^` and is never declared as a type

*Cascade stub: one signal for one event. Track T agent (face 2) or the owning
dev track triages the root; individual tickets only for whatever remains red
after the root is fixed.*

## Log
- 2026-09-06 — auto-closed by the seven watcher: `cascade@562162b03a02` passes at d11b8a1a99dd (tier full); it was red at 562162b03a02. Reopening is by a fresh NEW-RED stub, since a second red is a second finding with its own range.
