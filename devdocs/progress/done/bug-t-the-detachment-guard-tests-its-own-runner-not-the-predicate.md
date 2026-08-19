---
slug: bug-t-the-detachment-guard-tests-its-own-runner-not-the-predicate
track: T
type: bug
prio: 55
status: done
blocked-by: []
summary: "tools-devtest#00 has been RED in every full tier since the job was created at a1fd5715e, and it is not a compiler regression. tstate_reader_devtest's detachment case asserted head_detached(THIS repo) is False — a property of the runner, not of the code — and a watcher clone is detached at the sha under test by design, so the one environment where the full tier runs was the one environment where the assertion could not hold. It also never exercised the True direction, the direction the whole rule rests on. Rewritten against a scratch repo, both directions pinned."
owner: plexus-T
---

# The detachment guard tested its own runner, not the predicate

## The finding

`tools-devtest#00` is red in the live full tier and is carried in the open
cascade at `bad=21f098e32a95` alongside 12 nilpy/riscv jobs over a 261-commit
range. It does not belong there. Its true first-bad is `a1fd5715e`
(2026-08-19T15:44:05Z) — the commit that *created the job* by wiring
`tools-devtest` into the Makefile and the full tier. It has never passed in the
watcher, not once.

The failing check, from `tools/tstate_reader_devtest.py`:

    assert twatch.head_detached(str(TOOLS.parent)) is False, \
        "a checkout on a branch was reported as detached"

`TOOLS.parent` is the repo the devtest is *running in*. Every dev checkout is on
a branch, so it passes locally. A **watcher clone is detached at the sha under
test for most of every cycle** — that is the premise stated in this very file's
own header docstring, three paragraphs above the assertion. So the guard was
green everywhere it did not matter and red in the only place the full tier runs.

## The shape

The recurring one: **a true fact about the wrong subject.** The check reports
truthfully on the question "is the checkout I am in on a branch?" while the
reader — and the job name — believe it answers "does `head_detached`
distinguish the two states?" Those coincide in a dev tree and diverge in the
watcher.

Worse, it only ever tested one direction. Nothing anywhere proved
`head_detached` returns True when detached — and True is the direction the whole
tstate-reader rule is built on. A `head_detached` that always returned False
would have passed this file while silently disabling the enforcement it exists
to provide.

## The fix

The case now builds a scratch git repo, commits, asserts False on the branch,
detaches to the sha, and asserts True. It answers the actual question and
answers it identically in a dev tree and in a watcher clone.

Verified by reproducing the exact failure: cloned this repo, detached it, ran
the OLD file → `FAIL detachment-is-detected` (the watcher's line, verbatim); ran
the NEW file in the same detached clone → green. `PXX_TRACK=T make tools-devtest`
green locally.

## Consequence for the open cascade

`cascade@21f098e32a95` lists `tools-devtest#00` among 13 jobs. That member is
answered: first-bad `a1fd5715e`, cause self-inflicted, not a compiler change,
and it is fixed. The other 12 (nilpy cpyext, riscv32 float, lib-test etree) are
untouched by this and remain a real cascade in someone else's lane. Track T
files those; it does not fix them.

## Note for the next guard

`make tools-devtest` runs in the watcher's clone, which is **detached, at an
arbitrary sha, mid-cycle**. A guard that reads its own repo's branch, mtimes,
`origin/master`, or working-tree tstate is testing the runner. Build a fixture.
