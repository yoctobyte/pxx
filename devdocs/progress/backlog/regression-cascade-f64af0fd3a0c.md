---
prio: 70
---

> **origin/master has advanced 6 commit(s) since this sha.** Re-verify at current HEAD before acting — the callback is tagged to the sha that was tested, which may no longer be the state of the tree.


# regression CASCADE: 17 jobs newly red in e70ec7bfc..f64af0fd3 (3 commits) — auto-filed by twatch

- **Type:** regression cascade (auto-filed by Track T watcher, host borg).
  Untriaged. 17 jobs went red in ONE sweep — treat as ONE root cause until
  triage proves otherwise; do NOT fan out per-job tickets.
- **Found:** 2026-09-22T17:02:28Z
- **Root-cause suspects in the red set:** none of the known root jobs (`fpc-bootstrap`, `selfhost-fixedpoint`). That is the ONLY heuristic applied here — it does not imply a harness event, and nothing in this filing looked at the build, the box or the range. See the Range section below for commits worth checking.

## Range
> **The named sha `f64af0fd3a0c` CANNOT be the cause** — it touches no buildable file (docs/tickets/tstate only). It is the sha that was TESTED, i.e. the upper bound of an untested range, and the cause is somewhere below it.

bad `f64af0fd3a0c`, last good `e70ec7bfc320`, **3 commit(s) in range** (3 of them buildable). **No idle bisect will happen** — the watcher skips cascades deliberately (one synthetic key matches no job), so this range is narrowed by hand or not at all.

**Buildable commits in the range, newest first:**
- `2fb85295cef4` docs(A): "returns 0" was false because the fix works -- a prose repair leaves one hit, and
- `d597cd47dbf6` docs(A): PasApplyDefaults has never existed -- three comments cited each other and no code
- `523833fde336` fix(A): an ambient unit written over managed strings must drag builtinheap -- five trigger

## Repro (start with a suspect, or any listed job)
`tools/testmgr.py --tier full --job '<job>'` at f64af0fd3a0cbd75138f2f38af5c99c665602792

(The sha above is the right one to REPRODUCE at — the jobs really are red
there — even when the Range section says it cannot be the CAUSE. Reproducing
and blaming are different questions and this line answers the first.)

## Newly red jobs
> Each job's own recorded failure REASON is printed under its name. **When the
> reasons and the Range section disagree, the reasons win.** The range is
> computed from what CHANGED, not from what the job can SEE — a missing guest
> loader, an absent dev package or a job that has never once passed on this box
> all produce a red that no commit in the range caused.

- `test-arm32#src:test/test_const_record_temp.pas`
  - pascal26:50: error: compiler error: PXXMemMove not found | near: ( p . x ) ; >>> end .
- `test-arm32#src:test/test_cross_aggregate_return.pas`
  - pascal26:12: error: compiler error: PXXMemMove not found | near: , n * 2 ) ; >>> end ; var
- `test-arm32#src:test/test_cross_byvalue_aggregate_params.pas`
  - pascal26:99: error: compiler error: PXXMemMove not found | near: ; begin CopyOut := r ; >>> end ; var
- `test-arm32#src:test/test_record_temp_byval_arg.pas`
  - pascal26:18: error: compiler error: PXXMemMove not found | near: ; writeln ( n ) ; >>> end .
- `test-arm32#src:test/test_set_runtime.pas`
  - pascal26:42: error: compiler error: PXXMemZero not found | near: , 3 in cand ) ; >>> end .
- `test-c-conformance#shard0/6`
  - pascal26:5980: error: compiler error: call to a runtime stub that was never emitted (code offset 0 is the ELF entry point). A frontend driver is missing its stub-emission call for the current flags/t…
- `test-c-conformance#shard1/6`
  - pascal26:5980: error: compiler error: call to a runtime stub that was never emitted (code offset 0 is the ELF entry point). A frontend driver is missing its stub-emission call for the current flags/t…
- `test-c-conformance#shard2/6`
  - pascal26:5980: error: compiler error: call to a runtime stub that was never emitted (code offset 0 is the ELF entry point). A frontend driver is missing its stub-emission call for the current flags/t…
- `test-c-conformance#shard3/6`
  - pascal26:5980: error: compiler error: call to a runtime stub that was never emitted (code offset 0 is the ELF entry point). A frontend driver is missing its stub-emission call for the current flags/t…
- `test-c-conformance#shard4/6`
  - pascal26:5980: error: compiler error: call to a runtime stub that was never emitted (code offset 0 is the ELF entry point). A frontend driver is missing its stub-emission call for the current flags/t…
- `test-c-conformance#shard5/6`
  - pascal26:5980: error: compiler error: call to a runtime stub that was never emitted (code offset 0 is the ELF entry point). A frontend driver is missing its stub-emission call for the current flags/t…
- `test-emit-obj#src:test/c_obj_data_dup_a.c`
  - pascal26:5980: error: compiler error: call to a runtime stub that was never emitted (code offset 0 is the ELF entry point). A frontend driver is missing its stub-emission call for the current flags/t…
- `test-emit-obj#src:test/c_obj_data_import.c`
  - pascal26:5980: error: compiler error: call to a runtime stub that was never emitted (code offset 0 is the ELF entry point). A frontend driver is missing its stub-emission call for the current flags/t…
- `test-emit-obj#src:tools/compiler_srchash.sh`
  - pascal26:5980: error: compiler error: call to a runtime stub that was never emitted (code offset 0 is the ELF entry point). A frontend driver is missing its stub-emission call for the current flags/t…
- `test-esp-bare#src:test/test_esp_record_result.pas`
  - -11 | -22 | -2130706433 | -8080 | -150 | esp32c3 record result MISMATCH
- `test-pascal-conformance#shard3/6`
  - pascal26:6: error: compiler error: call to a runtime stub that was never emitted (code offset 0 is the ELF entry point). A frontend driver is missing its stub-emission call for the current flags/targ…
- `test-record-abi-mixed-link#src:tools/compiler_srchash.sh`
  - test-record-abi-mixed-link: PXX C COMPILE FAIL x86_64 | first: the mistake would be at or before that file's last line. | near: Exit ; end ; end ; >>> end ; function | test-record-abi-mixed-link: PAS…

*Cascade stub: one signal for one event. Track T agent (face 2) or the owning
dev track triages the root; individual tickets only for whatever remains red
after the root is fixed.*
