---
slug: bug-t-89-nilpy-expectations-are-duplicated-across-two-targets-with-nothing-keeping-them-in-sync
track: T
prio: 50
type: bug
status: backlog
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
