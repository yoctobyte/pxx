---
prio: 70
track: T
status: done
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

## Not a bug — the sweep was asking the wrong question. 2026-09-01, frankZ.

`test/test_threadsafe_io_lock_foreign.pas` puts four foreign threads through
50 `Writeln`s each. **The order is nondeterministic by design and its own
header says so** — three runs of ONE binary at a fixed `-O` give three
different byte streams. optdiff compares raw stdout, so it reports DIFF by
construction, at every level, forever.

The property the program actually asserts is ATOMICITY: a `Writeln` is two
`write(2)` calls and without the I/O lock two threads interleave them into a
line that is not 300 identical characters. That is what its Makefile row asks
(`grep -c -E '^(A{300}|B{300}|C{300}|D{300})$'` must be 200, plus `done`), and
raw stdout comparison cannot express it.

Measured at HEAD (`b9fd008f89ef`), five runs at each of -O0/-O1/-O2/-O3:
**`200 done` twenty times out of twenty.** The invariant holds at every level;
only the order moves.

So this goes to `tools/optdiff.skip`, and the entry says which question is
being declined and which tool asks it instead. Note that this was NEVER the
same bug as the five-shard hang — that one was
[[bug-a-dce-miscompiles-every-threaded-program-and-o3-turns-it-on]], a timeout
(`rc 0 vs 124`) rather than an output divergence, which is exactly the
distinction frank-user drew when it said shard4 was a name collision. It was
right.
- 2026-09-02 — resolved; this names the commit that carried the resolve, which is not always the one that carried the change — commit PENDING-COMMIT.
