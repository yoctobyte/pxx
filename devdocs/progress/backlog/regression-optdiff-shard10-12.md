---
prio: 70
track: T
---

> **Track T by default: the FAILING STEP named no owner.** Line 1 of 1 is `tools/optdiff.sh --shard 10/12`. The job's own `src` (`tools/optdiff.sh`, 1 file(s)) is NOT used here on purpose: it is what the job compiles, not what broke, and guessing a lane from it is what sent three reds in one job to the wrong lane. This is a FALLBACK, not a finding — nothing says the defect is Track T's. Re-lane it before working it.

> **origin/master has advanced 6 commit(s) since this sha.** Re-verify at current HEAD before acting — the callback is tagged to the sha that was tested, which may no longer be the state of the tree.

# regression: optdiff#shard10/12 at 285208414d3f in step 1/1, `tools/optdiff.sh --shard 10/12` (auto-filed by twatch)

- **Type:** regression (auto-filed by Track T watcher, host seven, twatch `5666dc9dba23`).
  Untriaged.
- **Found:** 2026-09-07T21:29:28Z
- **Test source:** tools/optdiff.sh
- **Failing step:** line 1 of 1 of the job's recipe; it names `tools/optdiff.sh`.
  ```
  tools/optdiff.sh --shard 10/12
  ```

## Repro
`tools/testmgr.py --tier opt --job 'optdiff#shard10/12'` at 285208414d3f332c0b13f2a084e671fbad114be7

## Range
bad `unknown`, range **unknown** — there is no earlier passing sha to bound it, or the bound is not recorded. **No idle bisect will happen**; this one needs hand-triage.

## Log tail
```
OPT DIFF -O1: test/c_crtl_glob.c (rc 2 vs 2)
OPT DIFF -O2: test/c_crtl_glob.c (rc 2 vs 2)
OPT DIFF -O3: test/c_crtl_glob.c (rc 2 vs 2)
optdiff skip SKIPLIST: test_rtti_kind_numbering.pas
optdiff skip TIMEOUT-O0: c_unsigned_const_guard_folds.c test_qplus_narrowing_store.pas
optdiff skip BUILD-FAIL: c_ir_unsupported_reports_the_real_line.c c_obj_data_only.c c_obj_runtime_state_a.c c_pasunit_ansistring_result_fail.c c_unclosed_unsized_2d_init_fail.c c_undeclared_in_file_scope_init_refused.c cerror_directive_fail.c const_before_ctor_unit.pas cpasunit_strings.pas ctypes_lib.c except_b339_base.pas test_a_derailed_parse_names_the_appended_unit_as_the_compilers.pas test_a_half_dereferenced_call_result_is_refused.pas test_a_parameter_and_a_local_that_differ_only_in_case_are_two_symbols.pas test_an_interface_arity_mismatch_is_refused_fail.pas test_asm_rv32.pas test_bad_calls_all_report_fail.pas test_default_filefield_fail.pas test_default_textfile_fail.pas test_dynarray_in_a_variant_part_refused.pas test_generic_cycle_fail.pas test_generic_error_location_names_a_third_file_fail.pas test_generic_shadow_decl.pas test_header_static_body.pas test_overload_record_identity_fail.pas test_specialization_does_not_rename_after_a_dot.pas test_unit_finalization.pas test_unit_init_begin_form.pas test_unit_stray_token_refused.pas test_unterminated_comment_names_the_nested_brace.pas unit_c_bridge.pas
optdiff THREADSAFE-RETRY: test_atomic_counter.pas
optdiff shard 10/12: pass=186 skip=34 diff=1

```

*Stub ticket: signal only. Track T agent (face 2) enriches or a dev track
takes it from the repro line.*
