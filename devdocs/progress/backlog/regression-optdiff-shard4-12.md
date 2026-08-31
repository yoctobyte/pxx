---
prio: 70
track: T
---

> **Track T by default: the FAILING STEP named no owner.** Line 1 of 1 is `tools/optdiff.sh --shard 4/12`. The job's own `src` (`tools/optdiff.sh`, 1 file(s)) is NOT used here on purpose: it is what the job compiles, not what broke, and guessing a lane from it is what sent three reds in one job to the wrong lane. This is a FALLBACK, not a finding — nothing says the defect is Track T's. Re-lane it before working it.

> **origin/master has advanced 8 commit(s) since this sha.** Re-verify at current HEAD before acting — the callback is tagged to the sha that was tested, which may no longer be the state of the tree.

# regression: optdiff#shard4/12 at d74c7fbe9ffe in step 1/1, `tools/optdiff.sh --shard 4/12` (auto-filed by twatch)

- **Type:** regression (auto-filed by Track T watcher, host seven, twatch `802e5ed96a48`).
  Untriaged.
- **Found:** 2026-08-31T08:06:17Z
- **Test source:** tools/optdiff.sh
- **Failing step:** line 1 of 1 of the job's recipe; it names `tools/optdiff.sh`.
  ```
  tools/optdiff.sh --shard 4/12
  ```

## Repro
`tools/testmgr.py --tier opt --job 'optdiff#shard4/12'` at d74c7fbe9ffeca26a3991fcf80ca1d1b4318564d

## Range
bad `unknown`, range **unknown** — there is no earlier passing sha to bound it, or the bound is not recorded. **No idle bisect will happen**; this one needs hand-triage.

## Log tail
```
Terminated
OPT DIFF -O1: test/test_threadsafe_io_lock_foreign.pas (rc 0 vs 0)
OPT DIFF -O2: test/test_threadsafe_io_lock_foreign.pas (rc 0 vs 0)
OPT DIFF -O3: test/test_threadsafe_io_lock_foreign.pas (rc 0 vs 0)
optdiff skip TIMEOUT-O0: lib_mimic_urllib_request_server.pas test_signal_handlers.pas
optdiff skip BUILD-FAIL: c_cross_ns_arity.c c_def_hijack.c c_pasunit_missing_fail.c cpthread_needs_threadsafe_b.c csqlite_file_probe.c csqlite_suite.c except_b339_derived.pas kwpadprobe.pas macronest_fpcmode.pas macro_soup_lib.c test_auto_var_fail.pas test_four_independent_errors_report_fail.pas test_generic_constraint_longint_fail.pas test_incdiag_unit_fail.pas test_metaclass_narrowing_error.pas test_method_missing_args_report_fail.pas test_mode_delphi_unit_leak.pas test_parallel_for_capture.pas test_pascal_directive_error.pas test_sealed_abstract_method_fail.pas uopfrac.pas
optdiff shard 4/12: pass=160 skip=23 diff=1

```

*Stub ticket: signal only. Track T agent (face 2) enriches or a dev track
takes it from the repro line.*
