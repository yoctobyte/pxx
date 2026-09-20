---
slug: bug-n-two-npy-tests-write-one-testtmp-binary-and-one-asserts-differently-in-three-targets
title: "Two .npy tests compile to one $(TESTTMP) binary name, so one test's assertion runs the other's program"
track: N
prio: 55
type: bug
blocked-by: []
status: done
owner: ""
created: 2026-09-20
found-by: frankz-e5
summary: "MECHANISM: where two Makefile recipes compile different sources to the SAME $(TESTTMP) path, the second compile overwrites the first binary and the loser's assertion is executed against the winner's program -- a test that cannot fail for its own reason, diffed against its own .expected. The springing condition is any reuse of a binary basename across recipes; tools/npy_cross_target_expectation_devtest.py's t_no_new_binary_name_collision is the ratchet and names it. Live at 0ae279ae9: Makefile:2606 (test_nilpy_negative_zero_repr.npy) and Makefile:2708 (test_nilpy_negating_a_variant_zero_keeps_its_sign.npy) both write $(TESTTMP)/test_nilpy_negzero26 against DIFFERENT .expected files; the second rule was added 2026-09-16 by 334680199. The same guard's t_no_cross_target_expectation_drift is also red on test/test_nilpy_qualifier_vs_cproc.npy, which asserts different things in test-core:[25994], test-nilpy:[2514] and test-threads:[7471]. BOTH have been invisible since they landed because this guard reports through the aggregate tools-devtest#00, continuously red since 2026-09-12 with 182 consecutive still_red and zero transitions. Fixing either one is small; DE-SATURATING tools-devtest is what stops the next one hiding."
---

# What is wrong

Two independent defects, both surfaced by
`tools/npy_cross_target_expectation_devtest.py`, both in the NilPy test suite.
They are filed together because they are one guard's output in one subsystem,
and because the reason neither was noticed is common to both.

## 1. One binary name, two sources — the serious one

```
Makefile:2606   ./$(COMPILER) test/test_nilpy_negative_zero_repr.npy $(TESTTMP)/test_nilpy_negzero26
Makefile:2607   $(TESTTMP)/test_nilpy_negzero26 | diff -u test/test_nilpy_negative_zero_repr.expected -

Makefile:2708   ./$(COMPILER) test/test_nilpy_negating_a_variant_zero_keeps_its_sign.npy $(TESTTMP)/test_nilpy_negzero26
Makefile:2709   $(TESTTMP)/test_nilpy_negzero26 | diff -u test/test_nilpy_negating_a_variant_zero_keeps_its_sign.expected -
```

**Two different sources, one output path, two different `.expected` files.**
The guard's own words: *"Two tests compiling to one path overwrite each other,
and the loser's assertion then runs the winner's program."*

This is the house **"a guard that cannot fail"** class arriving by a route the
playbook did not previously cover — not a wrong assertion and not a wrong
population, but **a correct assertion executed against the wrong binary.**

Introduced by `334680199` (2026-09-16). **The fix is a one-word rename**; the
value is in the guard that found it, not in the repair.

## 2. One source asserting different things in three targets

```
test/test_nilpy_qualifier_vs_cproc.npy
    test-core:[25994]   test-nilpy:[2514]   test-threads:[7471]
```

The expectation is written out **verbatim** in each target, thousands of lines
apart, so editing one suggests nothing about the others. The guard
(`bb78dbc3d`) was built as a ratchet on a then-clean invariant precisely so
this would be caught on the first divergence. **It was. The report did not
travel.**

# Why neither was noticed

`tools/npy_cross_target_expectation_devtest.py` reports through
**`tools-devtest`**, an aggregate (`Makefile:39272`) that loops
`tools/*devtest*.py`, exits 1 if any member fails, and publishes under the
single opaque shard **`tools-devtest#00`**.

Measured 2026-09-20 via `python3 tools/twatch.py --job-history 'tools-devtest#00'`
against the tstate archive (682 runs all-time):

| fact | value |
| --- | --- |
| streak opened | `new_red` at `e115014ceb5e`, 2026-09-12T19:42Z |
| since then | **182 consecutive `still_red`**, zero transitions, through 09-20T12:51Z |
| what twatch's status line says | *"bad touches NO buildable file: it is the tested upper bound, not a lead"* |

**A saturated aggregate cannot report a new red inside it.** Both defects here
landed into an unchanging level, as did an unwired-test omission on 09-14
(fixed by `3d831675c`) and a hardcoded-`/tmp` recurrence
(`bug-n-a-nilpy-test-writes-a-fixed-tmp-path-so-concurrent-runs-race`).

**This consequence was PREDICTED on 2026-08-28** in that ticket's *Boundaries*
section — *"a red gate that everyone knows about stops being read"* — and
priced into its p45. The prediction was correct.

Write-up: `devdocs/dev/debugging-playbook.md`, "AN AGGREGATE JOB SATURATES".

# Boundaries

- **Found by the coordinator, which owns no lane and writes no code.** Both
  repairs are Track N's. Measured and handed over deliberately unfixed.
- Oracle for every number here: `make tools-devtest` at `0ae279ae9`, reading
  the job's own verdict line — `tools-devtest: 163 green, 2 RED` over **165 of
  the 166** files `tools/*devtest*.py` globs (the Makefile `case` skips
  `bench_timing`; see `chore-a-re-include-bench-timing-in-tools-devtest`).
- **The reporting-granularity question is NOT this ticket** and is adjacent to
  `bug-t-a-tier-job-identifier-is-a-selector-doing-double-duty-as-a-label`
  (T, p55), whose own text already notes that `#00` does not survive what
  `#src:` does. That ticket is about the identifier as a **label**; this
  mechanism is about it being too **coarse to carry an event**.

## 2026-09-20 — both repairs landed (frankS)

`35841d247`. `tools/npy_cross_target_expectation_devtest.py` rc=1 -> rc=0:

    ok   t_the_population_is_still_there      4768 blocks, 119 cross-target .npy sources, 4541 expectations
    ok   t_no_cross_target_expectation_drift  119 sources asserted identically in every target
    ok   t_no_new_binary_name_collision       15 known collisions, none new

**1 — the collision.** Renamed the variant-zero test's output to
`$(TESTTMP)/test_nilpy_negvarzero26`, leaving `test_nilpy_negzero26` to
`test_nilpy_negative_zero_repr.npy`, which held it first. `cmp` confirms the
two binaries genuinely differ, so the collision was live and not two names for
one program. A comment at the site says why the name is not the obvious one,
because the next person to add a variant-zero test will reach for `negzero26`.

**2 — the drift.** `test_nilpy_qualifier_vs_cproc.npy` is compiled in three
targets. `test-nilpy` and `test-core` both assert `main\nbye`; `test-threads`
asserted only `test -x $(TESTTMP)/test_tlsmixed26 && echo yes`. Replaced with
the same output assertion the other two make. **The two are not a trade:**
running the program implies it built, so the new row is strictly stronger than
the `test -x` it replaces, and all three targets now assert identically, which
is what leaves the ratchet nothing to hold. Measured before changing it — same
compile line, same flags, same binary, prints exactly `main` then `bye` — and
the new row fails when fed a wrong expectation.

**A correction to this ticket's own accounting, which matters for the count
everyone is quoting.** The collision was **one of TWO sub-guards inside one of
the two red guards**, not one of five peer defects: `npy_cross_target` has
three sub-guards and was red on two of them. Measured by stashing the Makefile
alone — HEAD showed two red sub-guards, the rename left one. So "five defects,
two guards" is right as a count of defects and wrong as a picture of the
structure, and a seat that fixed only the rename would have seen the aggregate
stay red and concluded the rename had not worked.

**`make tools-devtest` now prints `165 guard(s) green`**, zero red — the
saturation both this ticket and the 2026-08-28 one named is over, which is the
part worth more than either repair.

## Log
- 2026-09-20 — resolved; this names the commit that carried the resolve, which is not always the one that carried the change — commit 778d63ad3.
