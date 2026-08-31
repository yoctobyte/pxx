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

---

## 2026-08-30 — the escalation measurement was RUN. It does not hit, and it
## COULD NOT HAVE. Prio stays 50; the instrument is now fixed so a future run
## of it means something.

### What was measured

1155 published reports, 2026-07-07 → 2026-08-30, grepped for the signatures
this ticket named:

| signature | reports |
| --- | ---: |
| `Text file busy` | 3 |
| `ETXTBSY` | 0 |
| `: not found` | 1 |

And none of the four is this ticket's race:

- two are `/tmp/testmgr-scratch-*/pascal26-self` and `…/pascal26-next` — the
  **self-host chain**, which is the pair the Makefile comment records as
  "observed twice on 2026-08-02" and which was then fixed with
  compile-to-unique-name + `rename(2)`;
- one is `./compiler/pascal26: Text file busy` — the compiler binary itself,
  not a `$(TESTTMP)` path, a different mechanism;
- the `: not found` one is `cprintf_ll_b252_386`, which is written by **one
  source in one target** (`Makefile:8016`) and so is in neither the 15 nor the
  117. Its cause is elsewhere.

### Why a negative result here proves nothing — the measurement is blind by
### construction, and I proposed it

`tools/testmgr.py:352`:

```python
RUN_RETRY_SIGNATURES = ("Text file busy", "ETXTBSY")
```

**testmgr already retries exactly this.** A job whose log tail carries either
signature is re-run, and if the retry passes the job is marked `flaky` and
scored GREEN. So the event this ticket is about is *consumed by the harness
before it can reach a report* — and the report is what I told the next reader to
grep. A search whose blind spot is precisely its subject returns a confident NO
and cannot return anything else.

Same shape as counting `.expected` siblings to find unwired tests
([[done/chore-a-wire-the-nine-passing-orphan-tests-and-gate-check-test-wiring]]:
the proxy could only see subjects that had one, and would have reported "three"
for any true number). Recording it because I wrote the bad measurement into this
ticket myself, as the thing that would settle it.

### The retry ticket and this one are the two halves of one defect

[[done/bug-t-etxtbsy-race-reds-single-shot-selfhost-jobs]] closed by adding that
retry — and the comment it left in the source says the rest out loud:

> Root cause belongs in the recipe (write under a temp name and rename into
> place, atomic on one filesystem)

**This ticket is that root cause**, arrived at independently from the name map
rather than from a red. That ticket suppressed the symptom and named the cure;
this one is the cure, for 117 paths instead of three.

### Fixed here: the flake population is no longer unmeasurable

testmgr has always put `"flaky": [...]` in its result JSON. `twatch.py` — the
publisher — **never read the field**: `grep -n flaky tools/twatch.py` returned
nothing, and not one of 1155 reports mentions a retry. A suppression with no
counter, which is what made the measurement above impossible rather than merely
negative.

The watcher now carries it: `flaky: N` sits in the report **header**, beside
`skips:` and `skip_holes:` and for the same stated reason — a field that appears
only when it has something to say cannot report finding nothing — and the job
NAMES are rendered when there are any, because names are what let a reader ask
whether one path keeps recurring.

Guarded by `tools/twatch_flaky_report_devtest.py`, 4 guards, each verified
against its own broken condition: the header field removed → 3 red; the details
block removed (the original defect exactly) → 1 red; clean → 4 green. One
instrument error recorded in its own comment — the header check split on the
first `---`, which is the YAML frontmatter opener, so it read an empty header
and reported every field missing against a correct report.

### So: prio stays 50, and the ticket is now ANSWERABLE

Nothing observed, and for the first time nothing observed is a fact about the
tree rather than about the instrument. The re-measurement, for whoever next
reads this: **grep the reports for `flaky:` with a nonzero count, and for names
in the frozen 15**, over reports published after this change. That is the
evidence that was being asked for; it did not exist until now.

Unchanged: the 117-recipe sweep is still not the move, and the frozen set in
`tools/npy_cross_target_expectation_devtest.py` still stops it growing.
