---
prio: 70
track: T
---

> **Track T by default: the FAILING STEP named no owner.** Line 1 of 1 is `tools/optdiff.sh --shard 6/12`. The job's own `src` (`tools/optdiff.sh`, 1 file(s)) is NOT used here on purpose: it is what the job compiles, not what broke, and guessing a lane from it is what sent three reds in one job to the wrong lane. This is a FALLBACK, not a finding — nothing says the defect is Track T's. Re-lane it before working it.

> **origin/master has advanced 6 commit(s) since this sha.** Re-verify at current HEAD before acting — the callback is tagged to the sha that was tested, which may no longer be the state of the tree.

# regression: optdiff#shard6/12 at 26db8523e829 in step 1/1, `tools/optdiff.sh --shard 6/12` (auto-filed by twatch)

- **Type:** regression (auto-filed by Track T watcher, host seven, twatch `065bb7eaf0d5`).
  Untriaged.
- **Found:** 2026-09-02T21:15:35Z
- **Test source:** tools/optdiff.sh
- **Failing step:** line 1 of 1 of the job's recipe; it names `tools/optdiff.sh`.
  ```
  tools/optdiff.sh --shard 6/12
  ```

## Repro
`tools/testmgr.py --tier opt --job 'optdiff#shard6/12'` at 26db8523e829a1078e5663fc72d1d0687864688c

## Range
bad `unknown`, range **unknown** — there is no earlier passing sha to bound it, or the bound is not recorded. **No idle bisect will happen**; this one needs hand-triage.

## Log tail
```
OPT DIFF -O1: test/test_shortstring_through_a_pointer.pas (rc 0 vs 0)
OPT DIFF -O2: test/test_shortstring_through_a_pointer.pas (rc 0 vs 0)
OPT DIFF -O3: test/test_shortstring_through_a_pointer.pas (rc 0 vs 0)
optdiff skip SKIPLIST: test_rtti_method_call_by_name.pas
optdiff skip TIMEOUT-O0: c_const_and_chain_dead_arm.c cgeneric_array_decay.c
optdiff skip BUILD-FAIL: c_obj_data_dup_b.c c_obj_extern_addr.c cprep_lib.c csqlite_schema_exec_probe.c cundeclared_type_cast_fail.c i386_pcrel_globals.c lib_synapse_transitive_unit.pas my_c_lib.c olf_pshadow.pas test_byref_arg_lvalue_refused.pas test_char_var_as_pchar_refused.pas test_ctor_arity_error.pas test_errors_across_routines_all_report_fail.pas test_exitcode_halt_in_finalization.pas test_exitcode_normal_end.pas test_generic_spec_per_unit.pas test_include_cycle_fails.pas test_interface_field_access_fail.pas test_method_arg_typecheck_fails.pas test_object_value_constructor_error.pas test_record_ctor_noparam_fail.pas test_sealed_class_fail.pas test_strict_overload_error.pas
optdiff THREADSAFE-RETRY: test_parallel_for_capture_callee.pas test_sched_reactor_exhaustion.pas test_signal_num_threads_race.pas
optdiff shard 6/12: pass=139 skip=26 diff=1

```

*Stub ticket: signal only. Track T agent (face 2) enriches or a dev track
takes it from the repro line.*
