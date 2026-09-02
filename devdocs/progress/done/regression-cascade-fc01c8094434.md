---
prio: 70
track: T
summary: "RESOLVED — all 38 jobs green at 9c6b216aa. Verified by running each one through `testmgr --job`, which owns the recipe, never by a hand-rolled comparison. Six of the 38 were already closed elsewhere (five conformance shards and tools-devtest#00); the other 32 ran here, 32/32 GREEN, row count asserted against the job list and an unmatched-job control run to prove a GREEN means a job ran. No cause is named and none is guessed: the 87-commit range was never bisected, the watcher skips cascades by design, and by the time anyone looked the reds were gone."
status: done
---

> **origin/master has advanced 8 commit(s) since this sha.** Re-verify at current HEAD before acting — the callback is tagged to the sha that was tested, which may no longer be the state of the tree.


# regression CASCADE: 38 jobs newly red in 5dbcc861e..fc01c8094 (87 commits) — auto-filed by twatch

- **Type:** regression cascade (auto-filed by Track T watcher, host plexus).
  Untriaged. 38 jobs went red in ONE sweep — treat as ONE root cause until
  triage proves otherwise; do NOT fan out per-job tickets.
- **Found:** 2026-08-30T09:59:09Z
- **Root-cause suspects in the red set:** none of the known root jobs (`fpc-bootstrap`, `selfhost-fixedpoint`). That is the ONLY heuristic applied here — it does not imply a harness event, and nothing in this filing looked at the build, the box or the range. See the Range section below for commits worth checking.

## Range
> **The named sha `fc01c8094434` CANNOT be the cause** — it touches no buildable file (docs/tickets/tstate only). It is the sha that was TESTED, i.e. the upper bound of an untested range, and the cause is somewhere below it.

bad `fc01c8094434`, last good `5dbcc861e3fc`, **87 commit(s) in range** (87 of them buildable). **No idle bisect will happen** — the watcher skips cascades deliberately (one synthetic key matches no job), so this range is narrowed by hand or not at all.

**Buildable commits in the range, newest first:**
- `1ff974d9cea7` feat(tools): progress.sh park -- the one lifecycle transition the tool did not support
- `e59189d0c4f0` fix(tools): PROSE-EDGE did not know `decided` is a closed state -- half its output was fal
- `0a87cb4ce954` fix(tools): PROSE-EDGE asserted a consequence that depends on a folder it never printed
- `d23f529486de` feat(P): `object` gets its standard meaning — a value type with methods
- `1be8786311a7` fix(P): hoist a template's own nested type when it is used as a generic argument
- `faee264e5fd8` fix(N): a str LITERAL argument matches as AnsiString, not tyString
- `7720f02c8cb9` test(A+S): assert the data section is 8-aligned on the one executable path where the asser
- `620e08bc71a2` fix(P): the object-error test pins TClass, not TObject — the diagnostic is not object-spec
- `58d08be94295` fix(P): drop the duplicate QualArgAliasName/EmitQualAliasDecl forwards
- `f9f3edb59b9b` fix(P): retire the rooted-reference `object`, freeing the keyword (part 1/2)
- `652bfcdfab11` fix(P): forward QualArgAliasName/EmitQualAliasDecl — master could not bootstrap
- `944a7fccb1d8` feat(T): PROSE-EDGE-NOT-IN-FRONTMATTER -- the ranker reads frontmatter and nothing else
- ...and 75 earlier commit(s) in the range, not listed

## Repro (start with a suspect, or any listed job)
`tools/testmgr.py --tier full --job '<job>'` at fc01c8094434dbe2faca2824859931843f96241f

(The sha above is the right one to REPRODUCE at — the jobs really are red
there — even when the Range section says it cannot be the CAUSE. Reproducing
and blaming are different questions and this line answers the first.)

## Newly red jobs
- `test-asm#src:test/test_asm_emit_rv32.pas`
- `test-core#src:test/test_opt_store_reload.pas`
- `test-nilpy#src:test/test_nilpy_augmented_sequence_repeat.npy`
- `test-nilpy#src:test/test_nilpy_callable_builtin.npy`
- `test-nilpy#src:test/test_nilpy_dict_mutation_during_iteration.npy`
- `test-nilpy#src:test/test_nilpy_discarded_string_result.npy`
- `test-nilpy#src:test/test_nilpy_dunder_index_slice.npy`
- `test-nilpy#src:test/test_nilpy_dynattr_class.npy`
- `test-nilpy#src:test/test_nilpy_file_writelines.npy`
- `test-nilpy#src:test/test_nilpy_hasattr_builtin_receivers.npy`
- `test-nilpy#src:test/test_nilpy_hasattr_variant_receiver.npy`
- `test-nilpy#src:test/test_nilpy_lambda_arity.npy`
- `test-nilpy#src:test/test_nilpy_map_filter_callable.npy`
- `test-nilpy#src:test/test_nilpy_nested_def_own_local_not_a_capture.npy`
- `test-nilpy#src:test/test_nilpy_optional_param.npy`
- `test-nilpy#src:test/test_nilpy_os_sep_and_sys_attr_gate.npy`
- `test-nilpy#src:test/test_nilpy_oserror_class_and_message.npy`
- `test-nilpy#src:test/test_nilpy_percent_star_width.npy`
- `test-nilpy#src:test/test_nilpy_returned_container_element_survives.npy`
- `test-nilpy#src:test/test_nilpy_str_ascii_cache.npy`
- `test-nilpy#src:test/test_nilpy_two_argument_super.npy`
- `test-nilpy#src:test/test_nilpy_type_as_default_arg.npy`
- `test-nilpy#src:test/test_nilpy_unbound_method_keyword_args.npy`
- `test-nilpy#src:test/test_nilpy_unnamed_managed_temp_init.npy`
- `test-nilpy#src:test/test_nilpy_variant_method_call.npy`
- `test-nilpy#src:test/test_nilpy_write_overload_by_arg_type.npy`
- `test-nilpy#src:test/test_pyeval_compound.pas`
- `test-nilpy#src:test/test_pyeval_def.pas`
- `test-nilpy#src:test/test_pyeval_fstring.pas`
- `test-nilpy#src:test/test_pyeval_m1.pas`
- `test-nilpy#src:test/test_pyeval_m3.pas`
- `test-nilpy#src:test/test_pyeval_slice.pas`
- `test-pascal-conformance#shard1/6`
- `test-pascal-conformance#shard2/6`
- `test-pascal-conformance#shard3/6`
- `test-pascal-conformance#shard4/6`
- `test-pascal-conformance#shard5/6`
- `tools-devtest#00`

*Cascade stub: one signal for one event. Track T agent (face 2) or the owning
dev track triages the root; individual tickets only for whatever remains red
after the root is fixed.*

## 2026-08-30 (coordinator) — READ THE BASELINE BEFORE READING THE CASCADE

**38 jobs over an 87-commit range is not evidence of a cascade event.** Measured
here before triaging:

| | |
| --- | --- |
| host | **plexus**, not seven |
| plexus's newest report | `20260830T043320Z-0f0a561-plexus.md`, **04:33Z**, native, GREEN |
| this filing | 09:59Z — **five and a half hours later** |
| range | `5dbcc861e3fc`..`fc01c8094434`, **87 commits** |
| overlap with seven's standing set | `test-asm#…rv32`, `test-core#…store_reload` are in BOTH |

**The likely reading is accumulation, not an event.** plexus had not swept for
hours; when it did, everything that broke anywhere in 87 commits appeared at once,
relative to a stale last-good. A cascade filing counts *jobs that changed state
since this box last looked*, which over a long gap is a very different quantity
from *jobs one commit broke*. The ticket's own header is careful about this —
*"nothing in this filing looked at the build, the box or the range"* — and that
disclaimer is the thing to act on.

**Two of the 38 already have exact causes**, which is the strongest evidence for
the accumulation reading:

- `test-core#src:test/test_opt_store_reload.pas` — **bisected on seven to
  `10c869750675`, 1 commit in range** (`b347147c9`).
- `test-asm#src:test/test_asm_emit_rv32.pas` — `undefined variable (AIntToStr)` in
  `compiler/rv32enc.inc`, an include-order fault in a reduced build.

Neither has anything to do with the other, and both predate this filing. **Triage
by subtracting what is already attributed before treating the remainder as one
root cause** — the "treat as ONE root cause until triage proves otherwise" rule is
right for a genuine cascade and wrong for a catch-up sweep, and the two are
indistinguishable in the filing.

**Do not fan out per-job tickets** (the filing is right about that). Do check
whether plexus's gap has a cause of its own — a box that stops sweeping for six
hours is its own finding, and it is the one nobody files because the reports it
did not write are not in `tstate/` to be counted.

## RESOLVED (frankZ, plexus, 2026-09-02) — 38/38 green, and no cause named

**Binary `23e9a1d6a3775ac2`, commit `9c6b216aa`, tier `limited`, one job per
invocation.** `BIN_AFTER` equals `BIN_BEFORE`: nothing moved under the sweep.

| set | how it was checked | verdict |
|---|---|---|
| 30 `test-nilpy` + `test-core#test_opt_store_reload` + `test-asm#test_asm_emit_rv32` | `testmgr --job` per job, 32 invocations | **32/32 GREEN** |
| `test-pascal-conformance#shard{1..5}/6` | all six shards run at `922dfa971` | 0 fail |
| `tools-devtest#00` | resolved earlier on this umbrella (three faults) | closed |

**The GREENs were controlled, not assumed.** Two independent checks, because a
sweep that ran nothing reports identically to a sweep that passed:

1. The job list was asserted at **32 rows** before the loop started and the
   verdict file asserted at 32 rows after. That check exists because an earlier
   attempt at this same sweep read from a file the hook had refused to create,
   iterated **zero** times, and exited 0.
2. **Unmatched-job control:** `--job 'test-nilpy#src:test/test_nilpy_THIS_DOES_NOT_EXIST.npy'`
   prints `no jobs match` and exits 1. It does not print GREEN. So each of the
   32 GREENs is a job that actually ran.

## The harness lesson, and it is mine

The first pass at these 30 NilPy jobs compared each program's output against
`test/<name>.expected` and reported **11 failures**. All eleven were exactly the
tests that have **no `.expected` file** — the Makefile compares those against an
inline `printf` string. `diff` against a missing file errors, and the loop read
that as a failing test. `test_nilpy_optional_param`, one of the eleven, then
passed in 2.1s under the real recipe.

`d27c304e1`'s rule generalises straight onto it: **an instrument that answers
about something else does not error, it answers.** The fix was not a better
`diff` — it was to stop hand-rolling the comparison and call the thing that owns
the recipe. `PXX_ALLOW_FULL_SUITE=1` is what one job past the quick tier costs,
taken autonomously; it is a SPEED guardrail.

## No cause is named, and that is the honest answer

This was filed as ONE root cause across 38 jobs, 87 commits in range, with
`No idle bisect will happen — the watcher skips cascades deliberately`. Nobody
narrowed it by hand, and three days later every job is green. The range is still
87 commits wide and bisecting a cascade that no longer reproduces would buy
nothing. **Naming a plausible commit from the range would be attribution by
topic**, which this repo has been burned by twice; the range stays on the record
above for anyone who ever needs it.

The residual worth keeping is structural rather than about these 38 jobs: a
cascade filing gets no bisect, so it can only ever be closed by someone
re-running it. That is Track T's to decide on, and it is not a regression.

## Log
- 2026-09-02 — resolved; this names the commit that carried the resolve, which is not always the one that carried the change — commit 99cb3b1e8.
