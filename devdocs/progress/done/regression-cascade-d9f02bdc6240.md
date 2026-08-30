---
prio: 70
---

> **origin/master has advanced 2 commit(s) since this sha.** Re-verify at current HEAD before acting — the callback is tagged to the sha that was tested, which may no longer be the state of the tree.


# regression CASCADE: 14 jobs newly red in 7acd2315e..d9f02bdc6 (3 commits) — auto-filed by twatch

- **Type:** regression cascade (auto-filed by Track T watcher, host seven).
  Untriaged. 14 jobs went red in ONE sweep — treat as ONE root cause until
  triage proves otherwise; do NOT fan out per-job tickets.
- **Found:** 2026-08-30T22:43:36Z
- **Root-cause suspects in the red set:** none of the known root jobs (`fpc-bootstrap`, `selfhost-fixedpoint`). That is the ONLY heuristic applied here — it does not imply a harness event, and nothing in this filing looked at the build, the box or the range. See the Range section below for commits worth checking.

## Range
> **The named sha `d9f02bdc6240` CANNOT be the cause** — it touches no buildable file (docs/tickets/tstate only). It is the sha that was TESTED, i.e. the upper bound of an untested range, and the cause is somewhere below it.

bad `d9f02bdc6240`, last good `7acd2315e72c`, **3 commit(s) in range** (3 of them buildable). **No idle bisect will happen** — the watcher skips cascades deliberately (one synthetic key matches no job), so this range is narrowed by hand or not at all.

**Buildable commits in the range, newest first:**
- `96f92002f675` fix(A+S): an xtensa BACKWARD jump past J's 128 KiB now widens, at zero cost to every jump 
- `05580b5f77a5` measure(O): NilPy subscript re-measured — headline halved, every named driver gone
- `1a4c05d8156d` fix(A+S): the xtensa frame is a patched LITERAL, not a chain of ADDMIs — replacing 0d21318

## Repro (start with a suspect, or any listed job)
`tools/testmgr.py --tier full --job '<job>'` at d9f02bdc62402bbcdcd5743b86f9de516b464700

(The sha above is the right one to REPRODUCE at — the jobs really are red
there — even when the Range section says it cannot be the CAUSE. Reproducing
and blaming are different questions and this line answers the first.)

## Newly red jobs
- `test-xtensa#src:test/test_call_result_member.pas`
- `test-xtensa#src:test/test_const_record_temp.pas`
- `test-xtensa#src:test/test_const_record_temp_managed.pas`
- `test-xtensa#src:test/test_cross_aggregate_return.pas`
- `test-xtensa#src:test/test_cross_aggregate_stackargs.pas`
- `test-xtensa#src:test/test_cross_set_param.pas`
- `test-xtensa#src:test/test_interface_arc_exc.pas`
- `test-xtensa#src:test/test_interfaces_param.pas`
- `test-xtensa#src:test/test_managed_record_temp_init.pas`
- `test-xtensa#src:test/test_record_temp_byval_arg.pas`
- `test-xtensa#src:test/test_rtti.pas`
- `test-xtensa#src:test/test_single_in_aggregate.pas`
- `test-xtensa#src:test/test_stackless_gen.pas`
- `test-xtensa#src:test/test_streaming.pas`

*Cascade stub: one signal for one event. Track T agent (face 2) or the owning
dev track triages the root; individual tickets only for whatever remains red
after the root is fixed.*

## Log
- 2026-08-30 — auto-closed by the seven watcher: `cascade@d9f02bdc6240` passes at 62faeb055ce1 (tier full); it was red at d9f02bdc6240. Reopening is by a fresh NEW-RED stub, since a second red is a second finding with its own range.
