---
track: A
prio: 55
type: chore
owner: unassigned
blocked-by: []
summary: "DECIDED 2026-08-19: SWEEP the ~61 unwired test files into the suite — one job, not 61 tickets. Track A, not T, precisely because A can FIX a red in place; T would have had to file one per red. These are repro tests from fix commits that were never wired, so the bug already has a ticket in done/ — reference it, do not re-file. Never record current output as the expectation."
---

# Sweep the unwired tests into the suite

**Implements [[decide-what-an-unwired-test-may-assert]]** (user, 2026-08-19).

## Track A, and the lane choice is the whole design

This was first filed under Track T — test infrastructure, T owns the wiring tool, T did
the original triage. **The user rejected that, and the reasoning is the important part:**

> "It may lead to a waterfall of tickets. So if Track T is the wrong choice, make it
> Track A. And just sweep it — not a new ticket for everything that was already ticketed
> and fixed."

T is bound by *"T owns the tool, never the bug"*, so under T **every red must become a
ticket for another lane**. With ~61 files that is a ticket factory, and the handoff cost
would exceed the work. **Track A can fix a red in place**, so the same job is a *sweep*:
one unit of work, a handful of commits.

**Consequence: this is one job with one owner, not 61 items.** Do not decompose it into a
ticket per file.

## What the files are — measured, and it sets the method

`tools/check_test_wiring.py` found 98 test files no build rule runs; 10 are now wired. Of
the remaining 85: **61 compile today**, 5 are helper modules correctly not rules, ~5 need
particular flags, ~10 are blocked by a compiler error.

**Every one of the 30 most recent commits that added a file under `test/` is a `fix(...)`
or `feat(...)`.** They are repro tests written alongside real bug fixes and never wired —
an omission at the last step, not a judgement of worth.

## Method

1. Find the adding commit: `git log --diff-filter=A -- <file>`.
2. **Fix/feat commit** → wire the test to assert the behaviour that commit describes, and
   **write the commit sha into the expected file** so the provenance is visible rather
   than lost.
3. **No fix commit, no ticket, no discernible intent** → genuine leftover, delete it.
4. **Commit does not say what the right output is** → use the reference oracle
   (`tools/fpc_diff_probe.sh`, `gcc_diff_probe.sh`, `pydiff.py`). If that is not
   conclusive either, park the file and move on — do not guess and do not stall the sweep.
5. Where the source is legal input to the reference implementation, prefer the
   **dual-runnable** form (`test/lib_mimic_warnings.npy`): valid CPython *and* valid
   NilPy, asserting only the subset both agree on, so the oracle is a property of the file
   rather than a step that expires. Natural for NilPy, plausible for C, not for Pascal.
6. **Assert a COUNT as well as the content** — otherwise a test that silently stops
   emitting half its assertions still passes.

## Tickets: reference, do not re-file

**The bug already has a ticket, and it is in `done/`.** These files were created by fix
commits, so a red means either a regression of something already recorded, or a test that
was never quite right. Neither needs a new ticket in the ordinary case.

- **Red you can fix** → fix it in the sweep. No ticket.
- **Red that is a regression of a known bug** → **reference the original ticket** (the
  adding commit names it); do not open a duplicate.
- **File a new ticket ONLY** for something genuinely new, genuinely deep, and out of scope
  for the sweep — and then park that file rather than letting it hold up the rest.

**Grep `done/` before filing anything.** A resolved ticket re-filed as new work is a
documented recurring failure here.

## The one rule that does not bend

**Never record current output as the expectation.** A test built that way cannot fail for
the reason tests exist — it detects *change*, not *wrongness*, and defends a bug as
loyally as a correct value. If the right answer is unknown and the oracle cannot settle
it, park the file (step 4). Parking is cheap; a false expectation with a green tick in
front of it is not.

## Practical

- Wiring edits the **Makefile**. A owns it, so no cross-lane collision — but keep the
  batch coherent rather than dribbling edits across days.
- Gate as normal for A: `make compiler/pascal26` (the byte-identical self-host fixedpoint)
  + `tools/gate.sh quick`. The newly wired tests then ride Track T's matrix from the
  pushed sha onward, which is the actual payoff.
- **Sample caveat:** the 30 sampled additions are recent work. Sample the older tail
  first — if those are scruffier, step 3 (delete) applies more often than assumed.
