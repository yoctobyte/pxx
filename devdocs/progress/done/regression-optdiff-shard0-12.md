---
prio: 80
track: A
tags: [optimiser, O3, float, silent-wrong-value, unfixed-arm]
status: done
---

> **TRIAGED 2026-09-16 (frankuser). RE-LANED T -> A, and it is a REAL SILENT WRONG
> VALUE AT -O3.** The Track T default was correct to be a fallback: the defect is not
> the harness. **This is the uncovered `-O3` ARM of
> [[bug-a-a-float-assigned-to-an-integer-lvalue-moves-the-bits-instead-of-converting]],
> which is in `done/`** — the general case was fixed and `-O3` was never checked.
>
> **Minimal repro, and `-O3` is the only level that is wrong:**
>
> ```pascal
> program m;
> function RetInt(F: Double): Integer;
> begin
>   Result := F;
> end;
> var v: Integer;
> begin v := RetInt(4.7); WriteLn(v); end.
> ```
>
> | level | output |
> | --- | --- |
> | -O0 | `5` |
> | -O1 | `5` |
> | -O2 | `5` |
> | **-O3** | **`-858993459`** |
>
> The full fixture prints `got 4616977747989548237 want 5`, and
> `struct.unpack('<d', struct.pack('<Q', 4616977747989548237))` is **4.7** — the raw
> double bit pattern, not a number. So at `-O3` the float->int conversion on a
> function RESULT is dropped and the bits are moved, exactly the parent bug's
> signature.
>
> **Why this is worth prio 80 and not 70:** `-O3` is on track for `-O2` (CLAUDE.md),
> and this is a wrong VALUE with no diagnostic in an utterly ordinary construct. It
> does not crash; it returns a plausible-looking integer.
>
> **NOT a harness artefact — checked, because the two sibling shards WERE.** frankb-56
> closed optdiff shard2/shard10 on 2026-09-16 (`311649be0`): those compared `argv[0]`,
> which differs per `-O` level directory, so nine days of red were a path string. I
> re-ran this row under the new `OPTDIFF_FILES` and then compared the program's own
> stdout directly at `-O0` and `-O3`. It differs. **`test_c_gtk3_stock.pas`
> (shard5) PASSES on a direct re-run and should be re-verified before anyone works
> it.**

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

---

## RESOLVED 2026-09-16 (frankS, Track O/A) — `84ccb6384`

**The parent's `-O3` arm was the INLINER, not a second copy of the conversion rule.**

`ir.inc`'s float→int rewrite (wrap the RHS in the `-204` Round intrinsic) lives in the
**`AN_ASSIGN` lowering**. For a single-statement body `Result := <float expr>` the
inliner takes **shape 1**, which retains only the RHS *expression* and discards the
`AN_ASSIGN`. Probed at the top of that arm: **zero** inlined assignments with a float
RHS ever reach it. Nothing was wrong with the conversion — there was no assignment
left to convert.

What isolates it: out-of-line at `-O3` is correct, and the same body written to a
**local** rather than `Result` is correct at `-O3` (`viaResult=-858993459`
vs `viaLocal=5`). Shape 3 allocates a properly typed Result temp and stores through
it, which *is* an `AN_ASSIGN` and does get the rewrite.

**The fix reuses a precedent rather than adding a rule.** The guard directly above
already covered the **mirror** case — a conversion *into* a float result, the `D2S`
bug — and its own comment states the general rule: *"any RHS kind that is not ALREADY
the result kind goes to shape 3"*. The implemented predicate was **narrower than its
own stated intent**: keyed on the RESULT being float, so structurally blind to a float
RHS landing in an integer result. Extended to the sibling, routing to
`TryRetainInlineStmtBody`. Deliberately not a copy of the rounding rule — `ir.inc`'s
arm says two dozen places build an `AN_ASSIGN` and exactly one lowers it.

**Measured, not assumed:**

| instrument | result |
| --- | --- |
| `PXXDBG=a.inline` on the repro | exactly ONE line moves: `RetInt shape=1` → `shape=3`. Still **RETAINED** — a change of shape, not a lost inline. |
| same, across `compiler/compiler.pas` | all **206** retentions byte-identical to pin v410 — the guard fires on nothing in the compiler's own source. The instrument is proven live by the one repro line that does move. |
| **positive control**: pin v410, byte-identical sources | still `-858993459`, `viaResult=-858993459`, `got 4616977747989548237 want 5`. This tree: `5` at `-O0/-O1/-O2/-O3`. |

`viaLocal=5` on **both** sides is the aiming check: the guard did not blanket-disable
the expression path, it diverted one shape.

**No new fixture.** The optdiff sweep is the designed instrument for an opt-level
disagreement and `test_double_to_integer_lvalue_rounds.pas` at `-O3` going green IS
the regression test; a bespoke Makefile row would duplicate it.

Self-host fixedpoint converged, `gate.sh quick` GREEN. **Inert for anything building
against `$(PXX_STABLE)` until the next pin.**
- 2026-09-16 — resolved; this names the commit that carried the resolve, which is not always the one that carried the change — commit 7c612d661.
