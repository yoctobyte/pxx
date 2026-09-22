---
prio: 70
track: T
---

> **Track T by default: the FAILING STEP named no owner.** Line 1 of 1 is `tools/optdiff.sh --shard 8/12`. The job's own `src` (`tools/optdiff.sh`, 1 file(s)) is NOT used here on purpose: it is what the job compiles, not what broke, and guessing a lane from it is what sent three reds in one job to the wrong lane. This is a FALLBACK, not a finding — nothing says the defect is Track T's. Re-lane it before working it.

> **origin/master has advanced 10 commit(s) since this sha.** Re-verify at current HEAD before acting — the callback is tagged to the sha that was tested, which may no longer be the state of the tree.

# regression: optdiff#shard8/12 at e70ec7bfc320 in step 1/1, `tools/optdiff.sh --shard 8/12` (auto-filed by twatch)

- **Type:** regression (auto-filed by Track T watcher, host borg, twatch `1f06bcf02d3f`).
  Untriaged.
- **Found:** 2026-09-22T15:43:59Z
- **Test source:** tools/optdiff.sh
- **Failing step:** line 1 of 1 of the job's recipe; it names `tools/optdiff.sh`.
  ```
  tools/optdiff.sh --shard 8/12
  ```

## Repro
`tools/testmgr.py --tier opt --job 'optdiff#shard8/12'` at e70ec7bfc3208437c87bf00c409921858482b406

## Range
bad `unknown`, range **unknown** — there is no earlier passing sha to bound it, or the bound is not recorded. **No idle bisect will happen**; this one needs hand-triage.

## Log tail
```
Segmentation fault
(tail)
OPT DIFF -O1: test/reloc_resolve_probe.c (rc 0 vs 0)
OPT DIFF -O2: test/reloc_resolve_probe.c (rc 0 vs 0)
OPT DIFF -O3: test/reloc_resolve_probe.c (rc 0 vs 0)
Segmentation fault
Segmentation fault
Segmentation fault
Segmentation fault
Terminated
Terminated
Terminated
Terminated
optdiff skip SKIPLIST: test_c_gtk_call.pas
optdiff skip EXEC-FAIL-O0: c_obj_import_host.c(127) c_obj_static_link_b.c(127) i386_pcrel_globals_host.c(127) test_dead_loop_back_edge.pas(127)
optdiff skip BUILD-FAIL: cbridge_via_unit.c cconst_negative_array_bound_fails.c c_obj_esp_export.c csqlite_thread_test.c ctypedef_lib.c cundeclared_type_value_pos.c lib_g2048.pas olf_cmath.c pascal_varargs_not_declared_rejected.pas quick_canary_uses.pas test_a_for_in_enumerator_needs_a_parameterless_movenext_operator.pas test_a_function_that_reads_a_threadvar_is_not_inlined_as_a_global.pas test_a_lifted_nested_routine_keeps_its_token_channels_diag.pas test_an_open_array_parameter_takes_no_default_in_a_record_method_fail.pas test_an_operator_definition_does_not_shift_the_token_channels_named.pas test_an_unspecialized_generic_as_a_pointer_target_fail.pas test_array_member_fail.pas test_asm_att_reject.pas test_assign_lvalue_shapes_fail.pas test_builtin_name_demote.pas test_const_shadows_routine_fail.pas test_conversion_operator_ambiguous_cast_is_refused.pas test_directive_if_typemix.pas test_file_read_size_mismatch_fail.pas test_forin_enum_holes_fail.pas test_forward_interface_constraint_fail.pas test_generic_body_end_counting.pas test_generic_method_across_a_uses_clause.pas test_mgmt_operators_array_refused.pas test_pascal_define_unit_scope_order2.pas test_record_published_fail.pas test_the_threadvar_area_is_a_command_line_knob.pas test_undefined_field_fail.pas tobject_unitname_unit.pas ucycle_c.pas uopcirca.pas
optdiff THREADSAFE-RETRY: test_parallel_for_private.pas test_tthread.pas
optdiff shard 8/12: pass=217 skip=41 diff=1

```

*Stub ticket: signal only. Track T agent (face 2) enriches or a dev track
takes it from the repro line.*
