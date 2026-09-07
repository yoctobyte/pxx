---
prio: 70
track: T
---

> **Track T by default: the FAILING STEP named no owner.** Line 1 of 1 is `tools/optdiff.sh --shard 0/12`. The job's own `src` (`tools/optdiff.sh`, 1 file(s)) is NOT used here on purpose: it is what the job compiles, not what broke, and guessing a lane from it is what sent three reds in one job to the wrong lane. This is a FALLBACK, not a finding — nothing says the defect is Track T's. Re-lane it before working it.

> **origin/master has advanced 6 commit(s) since this sha.** Re-verify at current HEAD before acting — the callback is tagged to the sha that was tested, which may no longer be the state of the tree.

# regression: optdiff#shard0/12 at 285208414d3f in step 1/1, `tools/optdiff.sh --shard 0/12` (auto-filed by twatch)

- **Type:** regression (auto-filed by Track T watcher, host seven, twatch `5666dc9dba23`).
  Untriaged.
- **Found:** 2026-09-07T21:29:28Z
- **Test source:** tools/optdiff.sh
- **Failing step:** line 1 of 1 of the job's recipe; it names `tools/optdiff.sh`.
  ```
  tools/optdiff.sh --shard 0/12
  ```

## Repro
`tools/testmgr.py --tier opt --job 'optdiff#shard0/12'` at 285208414d3f332c0b13f2a084e671fbad114be7

## Range
bad `unknown`, range **unknown** — there is no earlier passing sha to bound it, or the bound is not recorded. **No idle bisect will happen**; this one needs hand-triage.

## Log tail
```
OPT DIFF -O3: test/test_double_to_integer_lvalue_rounds.pas (rc 0 vs 0)
optdiff skip SKIPLIST: test_rtti_field_get_by_name.pas
optdiff skip TIMEOUT-O0: devtest_tls_native_seam.pas test_emit_obj.pas test_halt_from_worker_thread.pas
optdiff skip BUILD-FAIL: c_obj_fnptr_a.c case_sensitive_unit.pas kwarg_overload_unit.pas lib_synapse_tls_loopback.pas shadow_b.pas strhelperprobe.pas test_a_call_result_is_not_an_assignment_target_through_a_cast.pas test_a_used_unit_keeps_its_own_assertion_default.pas test_a_whole_array_destination_refuses_a_scalar.pas test_array_param_default_refused.pas test_file_element_type_fail.pas test_include_miss_fails.pas test_lazy_var_scope_fail.pas test_mgmt_operators_field_refused.pas test_pointer_alias_identity.pas test_scalar_member_fail.pas test_sealed_abstract_class_fail.pas test_shared_lib.c test_string_default_on_ordinal_param_fail.pas unit_end_shapes_b.pas
optdiff THREADSAFE-RETRY: test_halt_from_worker_thread.pas test_parallel_for_capture_aggr.pas test_parallel_for_capture_string.pas test_parallel_policy.pas test_parallel_policy_lang.pas test_thread_api_no_uses.pas test_threadsafe_heap_lock_release.pas test_threadsafe_i386_stress.pas
optdiff shard 0/12: pass=210 skip=24 diff=1

```

*Stub ticket: signal only. Track T agent (face 2) enriches or a dev track
takes it from the repro line.*
