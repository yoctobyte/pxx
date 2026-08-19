---
track: T
prio: 55
type: chore
owner: unassigned
blocked-by: []
summary: "DECIDED 2026-08-19: triage the ~61 unwired test files by the commit that ADDED them, not by running them against an oracle. Every one of the 30 most recent additions is a fix/feat commit — these are repro tests for real fixed bugs, dropped before the Makefile line. NEVER record current output as the expectation. Reds go to the owning lane, never to a softened expectation."
---

# Triage and wire the unwired tests

**Implements [[decide-what-an-unwired-test-may-assert]]** (user, 2026-08-19: *"triaging
it is, and I think this is Track T work"*). Filed as work because a decided ticket that is
never re-filed is invisible to `ready`/`next`.

## What these files actually are — measured, and it changes the job

`tools/check_test_wiring.py` found 98 test files no build rule runs. Ten had an
`.expected` sibling and are now wired. Of the remaining 85: **61 compile today**, 5 are
helper modules correctly not rules, ~5 need particular flags, ~10 are genuinely blocked
by a compiler error.

**Every one of the 30 most recent commits that added a file under `test/` is a `fix(...)`
or `feat(...)`.** These are **repro tests written alongside real bug fixes and never
wired** — an omission at the last step, not a judgement that they lack value. So:

- **Do NOT bulk-delete.** A repro for a fixed bug guards a failure that demonstrably
  happened once, in the exact shape that produced it.
- **Do NOT run 61 files against an oracle to derive expectations.** The expectation is
  usually stated in the commit that created the file.

## Procedure

1. Find the adding commit: `git log --diff-filter=A -- <file>`.
2. **Fix/feat commit** → wire the test to assert the behaviour that commit describes, and
   **write the commit sha into the expected file**. Provenance must be visible: the whole
   objection to recording our own output is that nothing afterwards says where the
   expectation came from.
3. **No fix commit, no ticket, no discernible intent** → genuine leftover, delete it.
4. **Commit does not say what the right output is** → fall back to the reference oracle
   (`tools/fpc_diff_probe.sh`, `gcc_diff_probe.sh`, `pydiff.py`), or **park and ask the
   owning lane**. Do not guess.
5. Where the source is legal input to the reference implementation, prefer the
   **dual-runnable** form (`test/lib_mimic_warnings.npy` is the worked example): the file
   is valid CPython *and* valid NilPy and asserts only the subset both agree on, so the
   oracle is a property of the file rather than a step that expires. Natural for NilPy,
   plausible for C, **not available for Pascal**.
6. **Assert a COUNT as well as the content.** A test that silently stops emitting half its
   assertions otherwise still passes.

## The rule that must not bend

**NEVER record current output as the expectation.** Such a test cannot fail for the reason
tests exist — it detects *change*, not *wrongness*, and will defend a bug as loyally as a
correct value.

**Some of these WILL go red when wired. That is the point.** A red goes to the owning lane
as a ticket (IR/codegen → A, dialect → P, NilPy → N, RTL → B). **Never adjust an
expectation to make a red test pass** — that is the forbidden option arriving through the
back door. *T owns the tool, never the bug.*

## Two practical notes

- **Makefile collision:** wiring means editing the Makefile, which is NOT in T's file list
  and is shared with Track A. Announce the batch rather than sprinkling edits across days.
- **Sample caveat:** the 30 sampled additions are recent work. Sample the older tail before
  assuming all 61 follow the pattern — if the older ones are scruffier, step 3 applies more
  often.

## Gate

Track T's own tooling gate; test the tooling with quick tiers and a scratch bare repo
rather than long runs.
