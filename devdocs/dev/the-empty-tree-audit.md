# The empty-tree audit

**One command, no suspicion required:** run every guard against a scratch tree
with an **empty `Makefile` and an empty `test/`**. A guard that still passes has
told you it was never measuring anything.

Sibling of **`a-success-message-is-not-a-verdict.md`**: that doc is about a green
whose *scope* nobody states, this one is about a green whose *population* is
empty. Same root — a report is read at the width of its name.

## The mechanism

Most guards assert a **negative**: no test file is unwired, no expected value has
drifted, no forbidden pattern appears. A negative is cheap to satisfy and there
are two ways to satisfy it:

1. the property genuinely holds over the corpus;
2. **there is no corpus.**

Nothing in the output distinguishes them, because both print the same word. A
glob that stopped matching, a renamed directory, a `git ls-files` that returns
nothing in a fresh worktree, a scan rooted at the wrong path — every one of them
converts a guard into a tautology, silently, while the guard's *name* goes on
claiming the coverage.

So the audit does not look for bugs. It **removes the corpus and asks who
notices**. That is why it needs no prior suspicion and cannot be argued with: a
guard that passes over nothing has stated its own emptiness.

## The procedure

```
mkdir -p /tmp/audit/test && : > /tmp/audit/Makefile
# for each guard: run it with the repo root pointed at the scratch tree
```

Then partition the results. **The partition is the deliverable, not the pass
count**:

| outcome | reading |
| --- | --- |
| **fails** over the empty tree | healthy — it noticed the corpus was gone |
| **passes**, but never reads the tree (builds its own `mkdtemp` fixture, or names the Makefile only in prose) | **correct by construction** — not a finding, and must be separated out or the audit reports a false rate |
| **passes**, and was supposed to be reading the tree | **the finding** |

That middle row is what makes the audit usable rather than alarming. Measured
2026-08-30 over the 19 guards touching a Makefile: 12 passed the empty tree, 10
of those correct by construction, **2 real**. Reporting "12 suspicious" would
have been true and useless.

## Reading a finding: the defect is usually one level up

Both real findings had their cause in the *subject*, not the guard.

**`check_test_wiring.py` printed its population count only inside the all-clear
branch.**

| state | printed |
| --- | --- |
| nothing wrong | `scanned N test subject(s)` |
| one advisory live | the advisory, **and no count at all** |

The instrument disclosed its scope exactly when its scope was not in question,
and went silent the moment there was a finding to weigh. Nobody audits a clean
run; the run you actually read is the one that has quietly stopped saying how
much it looked at. **No line was wrong — the `if` was.** The fix is to print the
denominator on every path, which is what lets the guard above it check anything
at all.

**A label asserted at writing time and never re-derived.** A comment reading
"rows are still ~536" while the check measured **561** behind a floor of **500**
— three numbers, one check, no two agreeing, every run green. The label is a
third measurement that nothing verifies, and it is the one a human believes.

## Disposal: the three options, and the one nobody reaches for

When a guard survives the audit, the reflexes are **strengthen it** or **delete
it**. Both destroy information. The third option is to **write its scope down**.

- **Dead check** — could not have failed under any input. *Delete it.*
- **Alive but narrow** — it measures something real, just not what its name
  suggests. *Record what it does and does not cover, in its own docstring.*
  Example: a guard comparing a report against a computed number stays green when
  both drift **together**; it is a consistency guard, and something else must be
  the correctness anchor. Say which, in the file.
- **Genuinely broken** — fix it, and fix the subject one level up.

## Choosing the bound: name the question, not the number

A guard that replaces an empty population with a floor must say which question
the floor answers.

- **Collapse detector** — "did the scanner stop seeing the corpus?" Set an order
  of magnitude below the live figure (250 against a live 2830). It fires on
  catastrophe and stays quiet through ordinary growth.
- **Ratchet** — "is this figure drifting?" Tracks closely, fires on movement,
  and needs a maintainer who will re-derive it.

**These are different jobs and one number cannot do both.** A collapse detector
"tightened" into a ratchet fires on every ordinary week of test-writing, and a
guard that cries wolf earns the habit of being scrolled past — which is worse
than no guard, because the name still claims the coverage. A number chosen
because it felt safe is the one that gets disabled six weeks later.

## The rule the audit keeps proving

**The rule you are enforcing is the one you will not apply to yourself.** The
first casualty of this audit was a guard written earlier the same session by the
agent running the audit. Apply it to your own files first — that is where it
will find something.

## Where the instances are recorded

- `tools/test_wiring_gate_devtest.py` — the floor, and why it is a collapse
  detector; the empty-tree measurement is in its comment.
- `tools/check_test_wiring.py` — the population line, now printed on every path.
- `tools/pasmith_ledger_throttle_devtest.py` — a guard that survives its own
  negative control, with the scope written into the docstring rather than the
  guard deleted.
