---
prio: 70
---

> **origin/master has advanced 2 commit(s) since this sha.** Re-verify at current HEAD before acting — the callback is tagged to the sha that was tested, which may no longer be the state of the tree.


# regression CASCADE: 30 jobs newly red in bebac3336..afc0da53c (1 commits) — auto-filed by twatch

- **Type:** regression cascade (auto-filed by Track T watcher, host seven).
  Untriaged. 30 jobs went red in ONE sweep — treat as ONE root cause until
  triage proves otherwise; do NOT fan out per-job tickets.
- **Found:** 2026-08-31T02:36:56Z
- **Root-cause suspects in the red set:** none of the known root jobs (`fpc-bootstrap`, `selfhost-fixedpoint`). That is the ONLY heuristic applied here — it does not imply a harness event, and nothing in this filing looked at the build, the box or the range. See the Range section below for commits worth checking.

## Range
> **The named sha `afc0da53c859` CANNOT be the cause** — it touches no buildable file (docs/tickets/tstate only). It is the sha that was TESTED, i.e. the upper bound of an untested range, and the cause is somewhere below it.

bad `afc0da53c859`, last good `bebac33366f5`, **1 commit(s) in range** (1 of them buildable). **No idle bisect will happen** — the watcher skips cascades deliberately (one synthetic key matches no job), so this range is narrowed by hand or not at all.

**Buildable commits in the range, newest first:**
- `76722e07f97c` fix(A): the exception shadow chain is per-thread, so two threads stop crashing

## Repro (start with a suspect, or any listed job)
`tools/testmgr.py --tier native --job '<job>'` at afc0da53c859d936039cbebc07b6c2e44ea0fb7e

(The sha above is the right one to REPRODUCE at — the jobs really are red
there — even when the Range section says it cannot be the CAUSE. Reproducing
and blaming are different questions and this line answers the first.)

## Newly red jobs
- `test-core#src:examples/tk/shadow_format_except.npy`
- `test-core#src:test/fpcv.pas@2`
- `test-core#src:test/test_exceptobject_intrinsic.pas`
- `test-core#src:test/test_fpc_compat_batch2.pas`
- `test-core#src:test/test_interface_arc_exc.pas`
- `test-core#src:test/test_managed_exception_cleanup.pas`
- `test-core#src:test/test_nilpy_augmented_assign_class_dunder.npy`
- `test-core#src:test/test_nilpy_augmented_assign_class_field.npy`
- `test-core#src:test/test_nilpy_augmented_dunder_subscript.npy`
- `test-core#src:test/test_nilpy_dunder_on_self_reaches_the_override.npy`
- `test-core#src:test/test_nilpy_float_methods_variant.npy`
- `test-core#src:test/test_nilpy_getitem_iteration_protocol.npy`
- `test-core#src:test/test_nilpy_iter_next_cursor.npy`
- `test-core#src:test/test_nilpy_missing_module_attr_is_attributeerror.npy`
- `test-core#src:test/test_nilpy_pyexception_bare_vs_qualified.npy`
- `test-core#src:test/test_nilpy_rtl_exception_surface.npy`
- `test-core#src:test/test_nilpy_setitem_through_a_variant_receiver.npy`
- `test-core#src:test/test_nilpy_star_forward.npy`
- `test-core#src:test/test_nilpy_subclass_a_builtin_type.npy`
- `test-core#src:test/test_nilpy_subscript_store_on_a_call_result.npy`
- `test-core#src:test/test_nilpy_try_else.npy`
- `test-core#src:test/test_nilpy_tuple_eq_round_enum.npy`
- `test-core#src:test/test_rtl_fpc_compat_helpers.pas`
- `test-core#src:test/test_uses_order_pylib_exception_a.pas`
- `test-core#src:test/test_uses_order_pylib_exception_b.pas`
- `test-core#src:test/test_variant_comparison_coerces_a_stringy_operand.pas`
- `test-core#src:test/test_variant_conversion_failure_is_catchable.pas`
- `test-core#src:test/test_variant_div_by_zero_raises.pas`
- `test-core#src:test/test_variant_string_to_boolean.pas`
- `test-smoke#src:test/quick_canary_nilpy.npy`

*Cascade stub: one signal for one event. Track T agent (face 2) or the owning
dev track triages the root; individual tickets only for whatever remains red
after the root is fixed.*

## Log
- 2026-08-31 — auto-closed by the seven watcher: `cascade@afc0da53c859` passes at 4449e9fe8a09 (tier native); it was red at afc0da53c859. Reopening is by a fresh NEW-RED stub, since a second red is a second finding with its own range.
