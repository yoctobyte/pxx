---
prio: 70
track: C
status: done
---

> **Track T by default: the FAILING STEP named no owner.** Line 1 of 1 is `tools/optdiff.sh --shard 2/12`. The job's own `src` (`tools/optdiff.sh`, 1 file(s)) is NOT used here on purpose: it is what the job compiles, not what broke, and guessing a lane from it is what sent three reds in one job to the wrong lane. This is a FALLBACK, not a finding — nothing says the defect is Track T's. Re-lane it before working it.

> **origin/master has advanced 6 commit(s) since this sha.** Re-verify at current HEAD before acting — the callback is tagged to the sha that was tested, which may no longer be the state of the tree.

# regression: optdiff#shard2/12 at 285208414d3f in step 1/1, `tools/optdiff.sh --shard 2/12` (auto-filed by twatch)

- **Type:** regression (auto-filed by Track T watcher, host seven, twatch `5666dc9dba23`).
  Untriaged.
- **Found:** 2026-09-07T21:29:28Z
- **Test source:** tools/optdiff.sh
- **Failing step:** line 1 of 1 of the job's recipe; it names `tools/optdiff.sh`.
  ```
  tools/optdiff.sh --shard 2/12
  ```

## Repro
`tools/testmgr.py --tier opt --job 'optdiff#shard2/12'` at 285208414d3f332c0b13f2a084e671fbad114be7

## Range
bad `unknown`, range **unknown** — there is no earlier passing sha to bound it, or the bound is not recorded. **No idle bisect will happen**; this one needs hand-triage.

## Log tail
```
OPT DIFF -O1: test/c_crtl_glob_no_leak.c (rc 2 vs 2)
OPT DIFF -O2: test/c_crtl_glob_no_leak.c (rc 2 vs 2)
OPT DIFF -O3: test/c_crtl_glob_no_leak.c (rc 2 vs 2)
optdiff skip SKIPLIST: test_thread_writeln_interleave.pas
optdiff skip TIMEOUT-O0: test_target_name_in_external_refusal.pas
optdiff skip BUILD-FAIL: aoc_ovl_unit_fmt.pas c_cpp_macro_arg_shapes.c c_pasunit_two_overloads_fail.c cabi_bridge.c cabi_intra.c csqlite_layout_probe.c cxtensa_obj.c isas_b325_base.pas lib_klondike.pas library_exports_unknown_name_fail.pas test_a_class_name_is_not_an_integer_constant_fail.pas test_a_forward_pointer_two_units_deep_still_resolves.pas test_a_procedural_type_without_a_default_still_refuses_a_short_call_fail.pas test_a_units_define_and_packing_do_not_reach_the_units_it_uses.pas test_array_range_too_large_fail.pas test_char_array_3d_row_not_a_string_fail.pas test_incdiag_main_fail.pas test_mode_delphi_unit_leak_off_fail.pas test_one_char_literal_not_a_typed_pointer_fails.pas test_ordinal_default_on_string_param_fail.pas test_pascal_define_unit_scope_order1.pas test_record_protected_fail.pas test_set_literal_wrong_enum_fail.pas test_unit_ambient_system_surface.pas uopcircb.pas
optdiff THREADSAFE-RETRY: lib_criticalsection_blocking.pas test_critsec_once.pas test_parallel_for_capture_scalar_types.pas test_signal_threads.pas test_thread_clone.pas test_threadsafe_refcount_lockfree.pas test_tthread_final.pas
optdiff shard 2/12: pass=200 skip=27 diff=1

```

*Stub ticket: signal only. Track T agent (face 2) enriches or a dev track
takes it from the repro line.*

## Resolution (2026-09-16, frankb-56, Track C)

**NOT A COMPILER DEFECT. The harness manufactured the difference, and the
difference was `argv[0]`.** optdiff built the four levels to four different
paths and compared stdout+stderr. `test/c_crtl_glob_no_leak.c` requires an argument,
optdiff supplies none, so it exits 2 on its usage line — and that line prints
`argv[0]`. The entire diff was the binary's own path:

    -usage: /tmp/optdiff.N/d0 ...
    +usage: /tmp/optdiff.N/d1 ...

`rc 2 vs 2` was the tell and it was in the ticket from the start: matching exit
codes on both sides mean the program ran to completion and disagreed only on
text. Fixed in tools/optdiff.sh by building every level to ONE path.

**THE COMPILER WAS NEVER IMPLICATED, AND I MEASURED THAT RATHER THAN INFERRING
IT.** Run properly with its argument at each level, c_crtl_glob_no_leak.c is byte-identical
across -O0/-O1/-O2/-O3 — an allocs-vs-frees census. This is the first time this
program has actually been swept at four O levels, because under optdiff it only
ever reached the usage path.

**RESIDUAL, AND IT IS NOT CLOSED BY THIS FIX — owner: Track T.** optdiff cannot
supply arguments, so any argument-taking program in the corpus is swept only on
its usage path and counts as a `pass`. After this fix these two pass honestly
(all four levels agree) while covering nothing, which is a guard that cannot
fail sitting inside the pass count. Sizing that population needs a full-corpus
run, which this seat's gate does not include.
- 2026-09-16 — resolved; this names the commit that carried the resolve, which is not always the one that carried the change — commit 311649be0.
