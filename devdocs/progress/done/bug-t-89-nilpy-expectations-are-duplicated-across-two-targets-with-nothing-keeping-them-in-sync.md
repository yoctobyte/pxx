---
slug: bug-t-89-nilpy-expectations-are-duplicated-across-two-targets-with-nothing-keeping-them-in-sync
track: T
prio: 50
type: bug
status: done
found: 2026-08-30
found-by: frankwasm (hit it), frank-coordinator (measured)
blocked-by: []
summary: "89 .npy tests are run by BOTH test-nilpy and test-core, with their expect_same expectation inlined verbatim in each -- the two copies sit ~9900 lines apart in the Makefile and nothing keeps them in sync. Measured drift today is ZERO, so this is a ratchet on a clean invariant, not a backlog: update one copy and the other target goes red with no indication that a second copy exists."
---

# 89 nilpy expectations are duplicated across two targets, with nothing keeping them in sync

## How it surfaced

frankwasm, extending `test_nilpy_iter_next_cursor.npy`:

> *That test is registered TWICE in the Makefile (lines 592 and 10485), each with its
> expectation inline via `expect_same.sh`. Updating one would have left the other
> failing. Anyone extending an existing nilpy test's output should `grep -c` its
> expect line before assuming there is one.*

The advice is right. The **reason** is not a duplicate registration — it is structural,
and that changes the fix:

- line **592** is inside `test-nilpy:` (target opens at 343), label suffix `.1`
- line **10485** is inside `test-core:` (target opens at 4244), label suffix `.2`

So the same test runs in **two targets by design**, and the expectation — often a
30-element `printf '%b'` string — is written out **verbatim in both places**.

## Measured, 2026-08-30, at HEAD

| quantity | count |
| --- | ---: |
| distinct test sources referenced in the Makefile | 2033 |
| referenced on more than one line | 417 |
| `.npy` tests **run** in more than one target | **89** |
| of those 89, pairs whose two expectations **differ** | **0** |

**Zero drift today.** That is the number that decides the shape of the fix: there is no
backlog to clean, so this is a **ratchet** — hold a currently-clean invariant so the
first divergence fails loudly, rather than a report that arrives with 89 findings and
teaches everyone to scroll past it (face 132a; the calibration argument is 129 and 134a).

## Why it will bite

The two copies are ~9,900 lines apart, so nothing about editing one suggests the other
exists. The failure is **silent at edit time and red in the other target later**, and
the other target is `test-core` — which the per-fix loop does not run. Under the
current gating rule that red reaches nobody until Track T's sweep, by which time the
edit is many commits back.

frankwasm avoided it only by grepping first, having been bitten by an adjacent trap in
the same session (see below).

## Proposed check

For every `.npy` source invoked in more than one target, assert the `expect_same.sh`
payloads are byte-identical. Population 89, current findings 0. Track T's own gate
(`testmgr --tier full` green) applies.

Deliberately **not** proposed: de-duplicating the expectations into a shared variable.
That is a larger Makefile change touching two big targets, and it is a *design* call
about whether `test-core` should re-run the nilpy set at all — file it as `decide-*`
if someone wants it, rather than folding it into a guard.

## Adjacent, same session, worth fixing under the same ticket

frankwasm appended to `test_nilpy_iter_next_cursor.expected`, **which did not exist**,
creating a 4-line file — other nilpy tests it had touched use `.expected`, this family
does not. The diff caught it at once (expected 4 lines, actual 25). But the general
form is worse than this instance:

> **A test that reads its expectations from a file the runner ignores passes forever
> while asserting nothing.**

Same family as face 33 (a capability nothing invokes) and 130 (guards that cannot fail).
A check that every `test/*.expected` file is actually referenced by some recipe would
have caught the stray file, and costs one grep.

---

## 2026-08-30 — FIXED as a ratchet. Two of the three keyings were wrong, and the
## adjacent half turned out to be a check that already exists and is not run.

### The ratchet

`tools/npy_cross_target_expectation_devtest.py`, collected by `tools-devtest`
(which testmgr's `quick` and `limited` tiers both run, so it is genuinely
gated). Three guards, 0 red. Re-measured at HEAD rather than taken from the
ticket:

| quantity | count |
| --- | ---: |
| `(target, source)` compile blocks parsed | 3133 |
| expectations attributed to a compile | 2814 |
| `.npy` sources compiled in **more than one target** | **111** |
| ...whose assertion SEQUENCE differs | **0** |

Confirms the ticket's finding. The population reads 111 rather than 89 because
it is keyed on the source file; see below for why that matters.

### The keying is the whole subtlety, and two obvious choices are both wrong

**Not the expect_same LABEL.** Its `.1` / `.2` suffix looks like a copy index
and is a sequence number WITHIN a target. Grouping by label stem reports **91
differing pairs** — every one of them false, because two assertions about one
binary (stdout and stderr, or a value and a line count) read as two copies of
one assertion. That number was produced, disbelieved, and thrown away rather
than reported; the ticket's own "0 differ" was the second data point that said
the instrument was wrong.

**Not the TESTTMP binary name either.** Keyed that way the answer is 1 drift,
also false: `test_nilpy_is_identity26` is compiled from *two different sources*.
Chasing that produced the finding below.

**The key is the SOURCE FILE**, and the value is the ordered sequence of
`expect_same.sh` payloads between its compile line and the next one. Both wrong
keyings would have shipped a guard that either cries wolf 91 times or reports a
name collision as an expectation drift.

### The finding that fell out: filed separately

[[bug-t-a-testtmp-binary-name-is-shared-by-two-tests-and-by-two-targets]] —
**117** `$(TESTTMP)` binary names are written from more than one TARGET, and
testmgr runs different targets' jobs concurrently in one per-PID scratch root,
so they race on one path; `split_jobs()` merges producer/consumer pairs only
*within* a target. That is the ETXTBSY window the self-host chain already solved
with compile-to-unique-name + rename, 20 lines away in the same file. **15**
names are written by two different SOURCES, **6** of those from two targets —
where a lost race is not a corrupt binary but a clean run of the *wrong program*
scored against the other test's expectation.

Not swept: 117 recipe edits is the batch shape that hides its one bad hunk, and
the producer/consumer scan reads those literal paths to decide what may not be
split apart. The 15 are **frozen** by the third guard here, so a sixteenth
fails; the rest is that ticket's.

### The `.expected` half: the check already exists, and nothing runs it

The ticket proposes "a check that every `test/*.expected` file is actually
referenced by some recipe... costs one grep". That check exists —
`tools/check_test_wiring.py`, which covers `.npy`/`.pas`/`.c`/`.lua`/`.fth`
subjects and treats `.expected` through its sibling deliberately, so a missing
pair reports once rather than twice. Writing a second one would be the
special-case that `devdocs/dev/normalise-dont-special-case.md` warns about.

**It is RED right now and no rule invokes it.** Three `.npy` tests are wired
into nothing:

```
test/test_nilpy_keyword_call_tuple_on_a_skipped_default.npy
test/test_nilpy_str_method_return_type_on_a_variable.npy
test/test_nilpy_str_method_vs_pascal_string_helper.npy
```

All three exist, have an `.expected` beside them, and **pass at HEAD** —
`pxx == .expected` for all three; the one CPython can parse also matches CPython
exactly, and the other two use `import 'file.pas' as x`, a NilPy extension
CPython rejects, so no external oracle exists for them.

And the Makefile says the gate is already there:

> `# The check_test_wiring gate below is what turns it into one.`

There is no such gate below it, or anywhere: `grep -rn check_test_wiring` finds
two comments and a mention in `gui_suite.sh`. A closing note asserting a gate
that was never wired — the same shape as the comment that caused
`regression-test-pascal-conformance-shard0-6-2` (*"a HEADER is followed by `=`;
a use never is"*), and its consequence is measurable: three new orphans have
accumulated since. That half belongs to
[[chore-a-wire-the-nine-passing-orphan-tests-and-gate-check-test-wiring]], which
is still open in `backlog/` and is where it is being finished, rather than being
folded in here.

### Guards verified against their own broken conditions

With the Makefile's sha checked before and after each edit, because a control
suite silently inherits whatever the previous control left behind:

| injected | result |
| --- | --- |
| one copy of a cross-target expectation edited (`tuple` → `TUPLE`) | 1 red, the drift guard, naming the source and both line sets |
| a second source made to write an existing binary name | 1 red, the collision guard, naming it |
| clean tree | 3 green |

The first guard is the one on the INSTRUMENT — block count, cross-target
population, expectation count — because the other two are negatives, and a
negative is worthless from a scanner that quietly stopped matching.

### Deliberately not done

De-duplicating the expectations into a shared variable, as the ticket says: it
is a design call about whether `test-core` should re-run the nilpy set at all,
and it belongs in a `decide-*` if anyone wants it.

### Gate

Static analysis only, no compiler change. `tools-devtest` collects the new file
automatically. Box load 9-18 throughout with two other testmgr runs on it, so no
timing here is a signal.

## Log
- 2026-08-30 — resolved, commit PENDING-COMMIT.
