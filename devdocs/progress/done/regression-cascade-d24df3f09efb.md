---
prio: 70
status: done
owner: frankwasm
---

> **origin/master has advanced 16 commit(s) since this sha.** Re-verify at current HEAD before acting — the callback is tagged to the sha that was tested, which may no longer be the state of the tree.


# regression CASCADE: 24 jobs newly red in fc9e258e1..d24df3f09 (22 commits) — auto-filed by twatch

- **Type:** regression cascade (auto-filed by Track T watcher, host seven).
  Untriaged. 24 jobs went red in ONE sweep — treat as ONE root cause until
  triage proves otherwise; do NOT fan out per-job tickets.
- **Found:** 2026-08-30T18:39:19Z
- **Root-cause suspects in the red set:** none of the known root jobs (`fpc-bootstrap`, `selfhost-fixedpoint`). That is the ONLY heuristic applied here — it does not imply a harness event, and nothing in this filing looked at the build, the box or the range. See the Range section below for commits worth checking.

## Range
bad `d24df3f09efb`, last good `fc9e258e1b71`, **22 commit(s) in range** (22 of them buildable). **No idle bisect will happen** — the watcher skips cascades deliberately (one synthetic key matches no job), so this range is narrowed by hand or not at all.

**Buildable commits in the range, newest first:**
- `d24df3f09efb` test(a): wire the nine unicodestring tests — NONE of them had ever run
- `4dae78ad925b` test(A): a lifetime regression test for a branch's managed temps -- nothing in the suite c
- `8b2acd9edce0` fix(A): a routine's param shape must reach the caller on all three registration paths
- `28b2851cd125` fix(P): a bodiless nested class no longer swallows the rest of the type section
- `0f8114b3e4c5` fix: LOGBOOK merge=union, and the fourth ghost-sha route
- `8ba3425d1d59` fix(A): a line marker now names the innermost enclosing .c, so module attribution resets o
- `d8bdb7c5daca` fix(board): a dead "do not claim" was sitting on top of the Track A queue
- `220caf0271ab` test(a): the jsonscanner wall itself, and it falls WITHOUT the define
- `400fe9ee5773` fix(T): the pin verify publishes a verdict and, now, the evidence for it
- `c38e53ff8f28` fix(T): a pin verify row measured nothing and said [] — record it instead
- `8216b339c32c` docs: name the day's highest-frequency failure — "the name is not the thing"
- `84d8f514f67a` test(a): the width conversion at a record-field and array-element destination
- ...and 10 earlier commit(s) in the range, not listed

## Repro (start with a suspect, or any listed job)
`tools/testmgr.py --tier full --job '<job>'` at d24df3f09efbee3a00d3c49f06754bca1a183341

(The sha above is the right one to REPRODUCE at — the jobs really are red
there — even when the Range section says it cannot be the CAUSE. Reproducing
and blaming are different questions and this line answers the first.)

## Newly red jobs
- `test-nilpy#src:test/test_nilpy_callable_to_str_param_fails.npy`
- `test-nilpy#src:test/test_nilpy_calling_a_non_callable.npy`
- `test-nilpy#src:test/test_nilpy_catchable_runtime_errors.npy`
- `test-nilpy#src:test/test_nilpy_dunder_index_sites.npy`
- `test-nilpy#src:test/test_nilpy_dunder_reflected.npy`
- `test-nilpy#src:test/test_nilpy_exception_no_leak.npy`
- `test-nilpy#src:test/test_nilpy_file_write_text.npy`
- `test-nilpy#src:test/test_nilpy_infer_return.npy`
- `test-nilpy#src:test/test_nilpy_int_float_dunders.npy`
- `test-nilpy#src:test/test_nilpy_int_of_an_expression.npy`
- `test-nilpy#src:test/test_nilpy_int_of_string_is_arbitrary_precision.npy`
- `test-nilpy#src:test/test_nilpy_int_promotion_default.npy`
- `test-nilpy#src:test/test_nilpy_int_str_builtins.npy`
- `test-nilpy#src:test/test_nilpy_one_char_string.npy`
- `test-nilpy#src:test/test_nilpy_operand_clash_messages.npy`
- `test-nilpy#src:test/test_nilpy_pathlib.npy`
- `test-nilpy#src:test/test_nilpy_pyexpr_semantics.npy`
- `test-nilpy#src:test/test_nilpy_static_mixed_type_guard.npy`
- `test-nilpy#src:test/test_nilpy_str_ascii_cache.npy`
- `test-nilpy#src:test/test_nilpy_str_mul_str_undefined.npy`
- `test-nilpy#src:test/test_nilpy_str_repeat_linear.npy`
- `test-nilpy#src:test/test_nilpy_to_bytes.npy`
- `test-nilpy#src:test/test_nilpy_typeerror_is_catchable.npy`
- `test-nilpy#src:test/test_nilpy_variant_operator_sweep.npy`

*Cascade stub: one signal for one event. Track T agent (face 2) or the owning
dev track triages the root; individual tickets only for whatever remains red
after the root is fixed.*

## Triage (frankwasm, at HEAD 8983444a8): already fixed before this was filed — 9588c8535, reverted in 72b4c47a7

**All 24 jobs are `test-nilpy` and the cause is inside the range.** It is
`9588c8535` (*"a string literal is already a managed handle — stop rebuilding
one per call"*), which made a string literal reaching a callee hand back a
shared `.data` handle without the `IR_ARG` tag that describes it moving with it.
The observable was `len("a" * 3)` → 285 instead of 3.

Two commands localise it without a build, and they are the whole triage:

```
git merge-base --is-ancestor 9588c8535 d24df3f09efb   # 0 -> in the history
git merge-base --is-ancestor 9588c8535 fc9e258e1b71   # 1 -> NOT below last-good
```

In the history of `bad` and not in the history of `last good` **is** inside the
range — the two-command form, rather than reading 22 subject lines.

`72b4c47a7` reverted it, and that revert is an ancestor of HEAD. So this cascade
was already discharged when twatch filed it: the watcher was testing
`d24df3f09efb` at 18:39Z while master had advanced 16 commits past it, and the
ticket's own header says so. This is the documented sampler lag (~18 commits
behind tip), working as designed — the finding was true of the sha it named.

**Verified rather than inferred.** All 24 sources compiled at HEAD with
fixedpoint `bb3a768b89a2` and their output diffed against the CPython oracle:
23 match exactly, and the 24th (`test_nilpy_callable_to_str_param_fails`) is a
NEGATIVE test whose recipe greps the compiler's refusal — it emits
`expects text for parameter "s"` as required. Zero divergences.

**A guard now exists that did not when this landed.** `89e58402a` put checks
24-27 — this exact repro, plus the variable form, a literal reaching a
parameter, and a literal re-evaluated 200x — into `quick_canary_nilpy`, which
runs in `gate.sh quick`. The class previously had no check between "it built"
and the full tier, which is why it reached the pin shadow. It also comes with a
comment at `compiler/ir.inc`'s `pystr_repeat` arm recording that the `IR_ARG`
tag there looks wrong, is not, and segfaults if changed alone (`bcd4e68a4`).

Nothing to fix. Resolved as already-fixed, with the localisation written down
because a 24-job cascade with "no idle bisect will happen" reads as expensive
and was two commands.

## Log
- 2026-08-30 — resolved, commit PENDING-COMMIT.
