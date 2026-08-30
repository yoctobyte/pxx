---
slug: bug-t-a-testtmp-binary-name-is-shared-by-two-tests-and-by-two-targets
track: T
prio: 50
type: bug
status: backlog
found: 2026-08-30
found-by: pxx-a5 (Track T face 2), while building the cross-target expectation ratchet
blocked-by: []
summary: "117 $(TESTTMP) binary names are written from more than one TARGET, and testmgr runs different targets' jobs concurrently in one scratch root — so two compiles race on one path, which is the ETXTBSY/half-written-binary window the self-host chain already solved with compile-to-unique-name + rename. 15 names are written by two different SOURCES, 6 of those from two targets, where the loser's assertion runs the winner's program. Not a backlog to clean by sweep: the fix is per-recipe and the population is frozen by a devtest so it cannot grow."
---

# A `$(TESTTMP)` binary name is shared by two tests, and by two targets

Found while building the ratchet for
[[bug-t-89-nilpy-expectations-are-duplicated-across-two-targets-with-nothing-keeping-them-in-sync]].
Keying that invariant correctly required knowing which recipes write which path,
and the answer was not the expected one.

## Measured at HEAD, 2026-08-30

| quantity | count |
| --- | ---: |
| distinct test sources compiled inside a target | 2441 |
| `$(TESTTMP)` binary names written from **more than one target** | **117** |
| binary names written by **two different sources** | **15** |
| ...of those, written from more than one target | **6** |

## Two different failures, and the second is the quiet one

**1. Two sources, one name.** 15 binary names are produced by two different
test sources — e.g. `$(TESTTMP)/test_nilpy_is_identity26` is compiled from both
`test_nilpy_is_identity.npy` and `test_nilpy_is_identity_vs_class_test.npy`.
Within one target this is safe by accident: the recipes run in order, so each
compile-then-assert pair completes before the next begins. It is safe for a
reason nobody wrote down, and nothing stops a third recipe landing between them.

**2. One name, two targets — the live one.** 117 names are written from more
than one target, and this is not held by recipe order at all. `test-nilpy` and
`test-core` are separate testmgr JOBS, `split_jobs(target, lines)` merges
producer/consumer pairs only **within** a target, and the run's privatized
scratch (`RUN_TMP`) is per-PID, not per-job. So two concurrent jobs write the
same absolute path.

That is precisely the window the Makefile's own self-host chain documents and
solved:

> one process writing the path another is about to exec is ETXTBSY, "Text file
> busy", a red that has nothing to do with the code (observed twice on
> 2026-08-02, test-core and test-smoke)

Its fix — compile to a PID-unique temp name and `rename(2)` it into place — is
right there in the same file, applied to three paths. These 117 did not get it.

**And the 6 in the intersection are worse than a race.** For those, the two
targets compile *different sources* to one name, so a lost race does not produce
a corrupt binary — it produces a **clean run of the wrong program**, scored
against the other test's expectation. A verdict about the wrong binary, which is
the same family as
[[done/bug-a-testtmp-defaults-to-a-path-every-checkout-shares]] one level in:

```
test_nilpy_clsattr26     test-core  test/test_nilpy_class_attr.npy
                         test-core  test/test_nilpy_class_attrs_with_ctor.npy
                         test-nilpy test/test_nilpy_class_attr.npy
                         test-nilpy test/test_nilpy_class_attrs_with_ctor.npy
test_nilpy_fromkeys26    test-core  test/test_nilpy_dict_fromkeys.npy
                         test-nilpy test/test_nilpy_dict_fromkeys.npy
                         test-nilpy test/test_nilpy_dict_fromkeys_any_iterable.npy
test_nilpy_is_identity26 test-core  test/test_nilpy_is_identity_vs_class_test.npy
                         test-nilpy test/test_nilpy_is_identity.npy
                         test-nilpy test/test_nilpy_is_identity_vs_class_test.npy
test_nilpy_mcall26       test-core  test/test_nilpy_method_on_call_result.npy
                         test-nilpy test/test_nilpy_method_call_result_assigned_to_a_local.npy
                         test-nilpy test/test_nilpy_method_on_call_result.npy
test_nilpy_nestcomp26    test-core  test/test_nilpy_nested_comp.npy
                         test-nilpy test/test_nilpy_nested_comp.npy
                         test-nilpy test/test_nilpy_nested_comprehension_over_range.npy
test_nilpy_subdunder26   test-core  test/test_nilpy_builtin_subclass_dunder_dispatch.npy
                         test-nilpy test/test_nilpy_builtin_subclass_dunder_dispatch.npy
                         test-nilpy test/test_nilpy_subscript_dunder_spellings.npy
```

## Why this is filed rather than swept

117 recipe edits is exactly the batch shape that hides its one bad hunk, and
the two failures want different repairs — a rename for the name collisions, a
unique-then-rename (or a per-target prefix) for the cross-target races. A blanket
pass would also have to keep the producer/consumer scan working, which reads
those literal paths to decide what may not be split apart.

The population is **frozen** meanwhile:
`tools/npy_cross_target_expectation_devtest.py` fails on a SIXTEENTH
two-source collision, so this cannot grow while it waits.

## Not yet measured, and it decides the priority

Whether the cross-target race has ever actually fired. Two ETXTBSY reds are on
the record for 2026-08-02 and were attributed to the self-host chain, which was
then fixed; if any later ETXTBSY or "not found" red exists in `tstate/` for a
job in this set, that is the evidence, and it would raise this well above 50.
Someone taking it should grep the tstate reports for `Text file busy` and for
`: not found` against these 117 names before choosing a repair.

## Repro

```
python3 tools/npy_cross_target_expectation_devtest.py   # the frozen set
```
The full listing is regenerable from the Makefile with the same scan the devtest
uses: group `$(COMPILER) <src> $(TESTTMP)/<bin>` by `<bin>` and report any with
more than one `<src>` or more than one enclosing target.
