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

## Re-measured 2026-09-16 (frankb-56) — does NOT reproduce standalone, on EITHER compiler

Not a claim that this is fixed, and not a claim to this ticket. Recorded so the
next reader does not re-derive it.

| measurement | result |
| --- | --- |
| current compiler, full optdiff comparison (-O0 vs -O1/-O2/-O3) | `pass=1 skip=0 diff=0` |
| PINNED compiler (predates every fix landed today), -O0 vs -O3 | no difference either |
| does the subject use `ParamStr(0)`/`argv[0]`? | **no** (0 occurrences) |

**The argv[0] harness fix (311649be0) does NOT explain this**, which is the
first thing to rule out given it closed two sibling shard tickets the same day:
neither subject reads its own path, so that fix cannot have touched them. The
flattering reading was checked and refused.

**What this does NOT establish.** A standalone re-run is not the shard
population. optdiff's own header warns that under full shard parallelism a tight
timeout "turns box load into false DIFFs", and these rows were produced under
that load. So "does not reproduce alone" is consistent with a load/timing
artefact AND with a real defect that needs the shard context — it does not
choose between them. The re-run that would decide it is the shard, not the file.

**What it does establish:** whatever this is, it is not the same cause as
`regression-optdiff-shard0-12` (a real `-O3` inliner dropped store, fixed in
84ccb6384) or as shard2/shard10 (argv[0], 311649be0). Those closed by two
different causes. Treating the remaining shard reds as ONE cause is not
supported by the three that have now closed.

### Correction to the block above (same seat, same day) — this ticket is not commensurable with the other shard reds, and MUST NOT be closed on a green

My measurements above stand. The FRAMING around them did not, and the
correction came from frankuser with evidence I did not have.

**I called this "a fifth open shard the shard-red count had not accounted
for". That was wrong, and it was wrong in the direction that inflates a
count** — the thing I had just finished criticising in someone else's tally.

**A SHARD NUMBER WAS NEVER AN IDENTITY.** `tools/optdiff.sh:89` says so in the
tree I was measuring in: membership used to be `n % NSHARD` over the glob, so
adding any test file shifted every later file into a different shard, and since
the shard index IS the job identity in tstate, one migration manufactured **a
phantom NEW-RED on the shard a failure moved TO and a phantom FIXED on the one
it left**. Observed 2026-08-01: one unchanged `crtl_libc_oracle.c` failure
re-filed itself three times walking shard 5 -> 0 -> 2 — three tickets, one
compiler bug. Fixed by a name hash, which is stable under insertion.

**This ticket's whole history is that phantom pair.** Per frankuser: its entire
tstate history is TWO runs, both on host `seven` (retired 2026-09-11) —
`new_red` 2026-09-02, `fixed` 2026-09-03, one transition each way, on exactly
the dates the positional defect was live. By contrast shard5-12 has 82 runs.
So this is bookkeeping debt from a defect that no longer exists.

**AND THAT IS NOT A LICENCE TO CLOSE IT — WHICH IS THE PART THAT MATTERS, AND
IT CUTS AGAINST MY OWN BLOCK ABOVE.** A phantom `fixed` row is no more evidence
of health than the phantom `new_red` beside it was evidence of harm; they are
the same artefact seen from two sides, and taking one as real while discarding
the other is just picking the convenient half. **My "passes standalone on both
compilers" row must not be used to close this either**, for the reason my own
caveat already gave: a standalone run is not the shard population. Two weak
non-reproductions do not add up to one clearance.

**What is actually open across the optdiff shard reds is optdiff#shard5/12.
One shard.** Not four, not five.

**Where the "one cause" intuition came from, recorded because it is reusable:**
it was TRUE before the sharding fix — one bug genuinely did manufacture several
shard tickets, and `done/bug-a-five-optdiff-shards-are-one-o3-threading-hang`
is that shape. The generalisation outlived the defect that made it correct.
A heuristic inherited from a closed ticket about a DIFFERENT set of shards is
the failure here, and it is not specific to anyone: **before reading several
shard reds as one cause, check whether the shard numbers were identities on the
dates those rows were written.**
