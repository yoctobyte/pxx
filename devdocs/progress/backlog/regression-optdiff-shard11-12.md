---
prio: 70
track: T
---

> **Track T by default: the FAILING STEP named no owner.** Line 1 of 1 is `tools/optdiff.sh --shard 11/12`. The job's own `src` (`tools/optdiff.sh`, 1 file(s)) is NOT used here on purpose: it is what the job compiles, not what broke, and guessing a lane from it is what sent three reds in one job to the wrong lane. This is a FALLBACK, not a finding — nothing says the defect is Track T's. Re-lane it before working it.

> **origin/master has advanced 6 commit(s) since this sha.** Re-verify at current HEAD before acting — the callback is tagged to the sha that was tested, which may no longer be the state of the tree.

# regression: optdiff#shard11/12 at b291b321f185 in step 1/1, `tools/optdiff.sh --shard 11/12` (auto-filed by twatch)

- **Type:** regression (auto-filed by Track T watcher, host borg, twatch `1d5c476a6328`).
  Untriaged.
- **Found:** 2026-09-18T13:03:40Z
- **Test source:** tools/optdiff.sh
- **Failing step:** line 1 of 1 of the job's recipe; it names `tools/optdiff.sh`.
  ```
  tools/optdiff.sh --shard 11/12
  ```

## Repro
`tools/testmgr.py --tier opt --job 'optdiff#shard11/12'` at b291b321f18566a7874e1e56b6483615b85140ce

## Range
> **The named sha `b291b321f185` CANNOT be the cause** — it touches no buildable file (docs / tickets / tstate only). It is the sha that was TESTED, i.e. the upper bound of an untested range; the cause is somewhere below it.

bad `b291b321f185`, last good `ad85bf019f96`, 32 commit(s) in range — the watcher narrows this by idle bisect; check tstate/TSTATE.md for the current range.

## Log tail
```
Segmentation fault
(tail)
Segmentation fault
OPT DIFF -O2: test/test_ro_data_literal_store.pas (rc 0 vs 139)
Segmentation fault
OPT DIFF -O3: test/test_ro_data_literal_store.pas (rc 0 vs 139)
optdiff skip SKIPLIST: test_c_gtk_types.pas
optdiff skip EXEC-FAIL-O0: c_obj_runtime_state_b.c(127) test_emit_obj_noexport.pas(127)
optdiff skip BUILD-FAIL: c_cross_ns_arity_fail.c cdefine_flag_b239.c c_pasunit_collide_fail.c cslicea_lib.c csrcwins.c cstray_toplevel_reject_b193.c c_unclosed_ptr_array_init_fail.c quick_canary_uses_fail.pas shadow_a.pas shd_unit_a.pas test_a_class_operator_body_has_no_self_fail.pas test_a_redeclared_interface_alias_resolves_in_its_own_scope.pas test_a_specialized_body_materialises_under_circular_uses.pas test_a_static_array_is_not_a_dynamic_array_fail.pas test_a_stray_token_in_a_record_body_is_refused.pas test_bad_arity_and_noncallable_all_report_fail.pas test_case_unit_lookup.pas test_char_value_to_a_pchar_parameter_fail.pas test_cond_compare_names_symbol_fail.pas test_decl_order_global_error.pas test_default_unspecialized_generic_fail.pas test_fgl_use.pas test_forward_pointer_to_an_undeclared_type_fail.pas test_generic_constraint_named_fail.pas test_generic_func_in_unit.pas test_helper_const_not_global_fail.pas test_include_fi_search.pas test_pascal_claim_crosses_units.pas test_p_empty_parens_at_a_bare_method_call_fail.pas test_pointer_member_fail.pas test_procedure_as_value_fail.pas test_record_self_field_fail.pas test_shared_lib_init.pas test_unit_impl_section_is_private_fail.pas
optdiff THREADSAFE-RETRY: test_clone_entry_with_a_hidden_result.pas test_parallel_reduction.pas test_setlen_in_parallel_for_body.pas
optdiff shard 11/12: pass=215 skip=37 diff=1

```

*Stub ticket: signal only. Track T agent (face 2) enriches or a dev track
takes it from the repro line.*

## Log
- 2026-09-22 — the borg watcher saw `optdiff#shard11/12` GREEN at d36af549ea5b (tier opt) and did NOT close this: the job's class is `opt`, which testmgr treats as runtime-nondeterministic (RUN_RETRY_CLASSES) — a single pass does not refute a red there. The green is recorded because it is evidence and because a ticket that stops moving with no reason reads as forgotten; closing this one is a human's call.
