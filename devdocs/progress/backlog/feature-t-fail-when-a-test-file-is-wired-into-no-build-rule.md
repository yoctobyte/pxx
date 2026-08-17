---
track: T
prio: 45
type: feature
blocked-by: []
summary: "A file in test/ is not a test until a build rule runs it. Two confirmed cases of a test that existed, passed, and was referenced by nothing — one ungated for two weeks. Proposed: a check (progress.sh check or testmgr) that fails when a test/*.expected or test/*.npy has no rule referencing it, converting the class from 'someone notices' to 'CI notices'."
---

# Fail when a test file is wired into no build rule

## The class

**Writing a test and confirming it passes are both true, and neither makes it
covered.** The assertion being made is "this is now gated", and the only fact
that establishes it is a build rule referencing the file. `test-core` and
`test-nilpy` both ENUMERATE their tests explicitly; neither globs.

## Confirmed instances (2, both found by eye, days apart)

| test | landed | found | ungated for |
| --- | --- | --- | --- |
| `test_method_shadows_builtin.pas` | with its feature | 2026-08-16 | since it landed — it even had a `Gate:` line and an `.expected` |
| `test_nilpy_kwargs_collector_forward.npy` | 2026-08-17 (`5aea881e5`) | same day, by the coordinator | caught before it mattered |

Both were caught by a human-equivalent noticing, which is the version that does
not survive everyone forgetting. The second was written by an agent that was at
that moment actively collecting instances of this very failure mode, and still
wrote "adding a permanent test" in its summary — which is the argument for a
mechanical check rather than a rule people are told to remember.

## Proposed check

For every `test/*.expected` (and every `test/*.npy` / `test/*.pas` with a
sibling `.expected`), assert that some build rule references it. Fail with the
list. Natural homes: `tools/progress.sh check` (already reports STATUS-DRIFT and
PENDING-COMMIT, same "the record disagrees with reality" family) or `testmgr`.

Expected false positives worth designing for: tests deliberately not wired
(`*_fail` refusal recipes, tests that are run only by a script rather than the
Makefile, corpus-driven ones). An allowlist file with a REASON per entry is
probably right — an unexplained exemption is the same invisible-work problem
one level down.

## Not yet measured — and why

The obvious first step is a sweep: for every `test/*`, is it referenced in the
Makefile. **It has not been run.** `.claude/hooks/no-full-suite.sh` refuses a
shell loop over a `test/` glob, which this matches, even though the loop would
only `grep` the Makefile and compile nothing. That is a false positive on the
merits, and the escape (`PXX_ALLOW_FULL_SUITE=1`) is gated on the user asking.

Two agents independently declined to reshape the command to slip past the hook.
Recorded because it matters for whoever picks this up: **get the sweep
authorised, do not route around the hook.** The count decides whether this is a
ticket or a one-off — if it is one or two, the check is still worth having; if
it is twenty, it is urgent.

Possible side finding for Track T: the hook pattern may be worth narrowing so a
read-only `grep` over `test/` is not treated as a ten-minute suite run. That is
T's own tooling and T's call.

## Gate

The check fails on a deliberately unwired test file and passes on the tree once
the real gaps are wired; `tools/testmgr.py --tier full` green for the tooling
change.
