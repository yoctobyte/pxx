---
prio: 70
track: T
---

> **Track T by default: the FAILING STEP named no owner.** Line 1 of 1 is `tools/optdiff.sh --shard 5/12`. The job's own `src` (`tools/optdiff.sh`, 1 file(s)) is NOT used here on purpose: it is what the job compiles, not what broke, and guessing a lane from it is what sent three reds in one job to the wrong lane. This is a FALLBACK, not a finding — nothing says the defect is Track T's. Re-lane it before working it.

> **origin/master has advanced 6 commit(s) since this sha.** Re-verify at current HEAD before acting — the callback is tagged to the sha that was tested, which may no longer be the state of the tree.

# regression: optdiff#shard5/12 at 285208414d3f in step 1/1, `tools/optdiff.sh --shard 5/12` (auto-filed by twatch)

- **Type:** regression (auto-filed by Track T watcher, host seven, twatch `5666dc9dba23`).
  Untriaged.
- **Found:** 2026-09-07T21:29:28Z
- **Test source:** tools/optdiff.sh
- **Failing step:** line 1 of 1 of the job's recipe; it names `tools/optdiff.sh`.
  ```
  tools/optdiff.sh --shard 5/12
  ```

## Repro
`tools/testmgr.py --tier opt --job 'optdiff#shard5/12'` at 285208414d3f332c0b13f2a084e671fbad114be7

## Range
bad `unknown`, range **unknown** — there is no earlier passing sha to bound it, or the bound is not recorded. **No idle bisect will happen**; this one needs hand-triage.

## Log tail
```
OPT DIFF -O1: test/test_c_gtk3_stock.pas (rc 1 vs 1)
OPT DIFF -O2: test/test_c_gtk3_stock.pas (rc 1 vs 1)
OPT DIFF -O3: test/test_c_gtk3_stock.pas (rc 1 vs 1)
optdiff skip SKIPLIST: test_multithreading.pas test_rtti.pas test_rtti_method_reflection_b254.pas
optdiff skip TIMEOUT-O0: test_assert_message_position.pas test_c_lazycasing.pas test_qplus_survives_ambient_units.pas test_xtensa_div_zero_check.pas
optdiff skip BUILD-FAIL: c_obj_data_dup_a.c c_obj_data_import.c c_obj_import_pascal.pas c_pasunit_ansistring_fail.c c_pasunit_case_fail.c casm_goto_fails.c cquickjs_prereq.c crtl_tiny_regex_header_smoke.c cundeclared_fnptr_arg_rejected_b167.c lib_synapse_ssl.pas library_exports_rename_fail.pas record_abi_mixed_link_main.c shd_unit_b.pas strict_dialect_theirs_unit.pas test_chr_of_a_variable_as_pchar_refused.pas test_delphi_generic_cross_unit.pas test_diags_survive_error_recovery_fail.pas test_forin_string_char_fail.pas test_generic_constraint_tclass_fail.pas test_generic_func_error_names_its_unit_fail.pas test_generic_impl_template_is_private_ok.pas test_header_static_body_ffi_control.pas test_length_of_a_set_fail.pas test_method_arg_typecheck_fails_str.pas test_object_reference_error.pas test_override_bogus_rejected.pas test_param_row_external_forward_fail.pas test_pascal_message_fatal_directive.pas test_record_class_var_anon_fail.pas test_record_class_var_fail.pas test_scalar_misuse_is_refused_fail.pas test_statement_start_is_refused_fail.pas test_unit_finalization_halt.pas test_unit_hint_directive_hu.pas unit_impl_fwd.pas unit_uses_in_bare.pas
optdiff THREADSAFE-RETRY: lib_classes_tthread.pas test_palthread.pas test_thread_heap.pas test_thread_heap_mixed.pas test_threadsafe_heap_lock_deadlock_diag.pas
optdiff shard 5/12: pass=176 skip=43 diff=1

```

*Stub ticket: signal only. Track T agent (face 2) enriches or a dev track
takes it from the repro line.*
