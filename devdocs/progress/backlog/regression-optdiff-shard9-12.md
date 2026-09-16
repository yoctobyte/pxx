---
prio: 70
track: T
---

> **Track T by default: the FAILING STEP named no owner.** Line 1 of 1 is `tools/optdiff.sh --shard 9/12`. The job's own `src` (`tools/optdiff.sh`, 1 file(s)) is NOT used here on purpose: it is what the job compiles, not what broke, and guessing a lane from it is what sent three reds in one job to the wrong lane. This is a FALLBACK, not a finding — nothing says the defect is Track T's. Re-lane it before working it.

> **origin/master has advanced 8 commit(s) since this sha.** Re-verify at current HEAD before acting — the callback is tagged to the sha that was tested, which may no longer be the state of the tree.

# regression: optdiff#shard9/12 at 7e6029dca4ca in step 1/1, `tools/optdiff.sh --shard 9/12` (auto-filed by twatch)

- **Type:** regression (auto-filed by Track T watcher, host borg, twatch `1d5c476a6328`).
  Untriaged.
- **Found:** 2026-09-16T15:40:53Z
- **Test source:** tools/optdiff.sh
- **Failing step:** line 1 of 1 of the job's recipe; it names `tools/optdiff.sh`.
  ```
  tools/optdiff.sh --shard 9/12
  ```

## Repro
`tools/testmgr.py --tier opt --job 'optdiff#shard9/12'` at 7e6029dca4cadefc2ab87f6b0b4a7252b9a9f194

## Range
> **The named sha `7e6029dca4ca` CANNOT be the cause** — it touches no buildable file (docs / tickets / tstate only). It is the sha that was TESTED, i.e. the upper bound of an untested range; the cause is somewhere below it.

bad `7e6029dca4ca`, last good `f02aaea62be9`, 12 commit(s) in range — the watcher narrows this by idle bisect; check tstate/TSTATE.md for the current range.

## Log tail
```
Segmentation fault
(tail)
OPT DIFF -O2: test/test_foreign_thread_exception_chain.pas (rc 217 vs 0)
Segmentation fault
OPT DIFF -O3: test/test_foreign_thread_exception_chain.pas (rc 217 vs 139)
optdiff skip EXEC-FAIL-O0: c_abi_struct_byval_main.c(127)
optdiff skip BUILD-FAIL: constinit.pas c_pasunit_ovl_fail.c exception_helper.pas initsec_b.pas library_exports_not_cdecl_fail.pas qualified_a.pas test_a_class_body_alias_does_not_leak_to_the_unit.pas test_a_cross_unit_specialized_method_sees_its_own_parameters.pas test_a_directive_after_the_final_end_reaches_a_used_unit.pas test_an_open_array_parameter_takes_no_default_in_a_free_routine_fail.pas test_an_overload_report_spells_an_array_argument_the_same_at_a_free_call.pas test_asm_arm32.pas test_a_unit_qualified_read_of_a_same_named_global.pas test_case_sensitive_error.pas test_computed_member_fail.pas test_diagnostic_names_the_right_unit.pas test_elfdynsym.pas test_field_access_on_an_operator_result_no_overload_refused.pas test_generic_body_binds_in_its_declaring_unit.pas test_generic_routine_type_parameter_arity.pas test_libmanifest.pas test_pascal_fatal_directive.pas test_setlength_cast_refusal.pas test_sizeof_error.pas test_tobject_root_methods_inside_a_unit.pas test_typed_const_named_undeclared_fail.pas test_typed_const_named_wrongkind_fail.pas ucyctail_a.pas unit_cabi_bridge.pas unit_cabi_intra.pas unit_stray_end.pas
optdiff THREADSAFE-RETRY: test_atomic64.pas test_foreign_thread_exception_chain.pas test_heap_magazine_foreign_thread.pas test_mutex.pas test_threadsafe_class_finalize_kinds.pas test_threadsafe_obj_refcount_atomic.pas test_tthread_sync.pas test_tthread_terminate.pas
optdiff shard 9/12: pass=210 skip=32 diff=1

```

*Stub ticket: signal only. Track T agent (face 2) enriches or a dev track
takes it from the repro line.*
