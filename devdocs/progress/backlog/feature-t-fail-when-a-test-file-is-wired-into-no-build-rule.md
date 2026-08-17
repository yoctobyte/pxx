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

## 2026-08-17 — BUILT, and the sweep says 98

`tools/check_test_wiring.py` (`bb1ec8ca5`). The ticket asked for the count
before deciding whether this is a ticket or a one-off. It is neither: it is a
backlog.

| | |
| --- | --- |
| naive (path in Makefile only) | 192 |
| **after following indirect wiring** | **98** |
| of those, with an `.expected` sibling | **10** |

### The two indirect passes are what make 98 credible

A checker reporting 192 would have been dismissed as noise on first contact, and
permanently. Both classes it now follows are genuinely "something runs it":

- **directory references** — `-Futest/case_units` names the dir, never
  `uPSUtils.pas`;
- **imports from a wired subject** — `uses` / `#include`, so `cenum_lib.c`
  counts as run because the test including it runs.

Roughly half the naive answer was real wiring reached indirectly. Same insight
as the corpus-hint fix: **an over-cautious signal has a cost, and it is paid
silently.**

### The 10 are the finding; the other 88 are the backlog

Every one traced landed **with a fix in the last two days** — a regression test
shipped alongside its own fix, running nowhere:

```
test_const_real_expressions.pas        8938aed7d  fix(P): real-valued constant expressions
test_for_limit_once_and_type_max.pas   dfc3b7449  fix(A): a for loop evaluates its limit once
test_set_symmetric_difference.pas      135db3071  feat(P): support >< (set symmetric difference)
test_local_typed_const_is_static.pas   3ed3e2653  fix(P): a routine-local typed const is static
test_integer_longint_overload.pas      (strict-overload-width work)
+ 5 test_nilpy_*.npy
```

That is a **different severity** from the other 88. A test that runs nowhere is
worse than no test, because it makes the fix look protected. Several of these
were confirmed green during triage **by hand** — which is exactly the
verification that does not survive everyone forgetting, and is the argument this
ticket opened with.

### Deliberately NOT gated yet

It would be red on arrival, which trains people to skip a step, and it would
gate other lanes on work they have not been given. Gating is the follow-up once
the real gaps are wired.

`test/UNWIRED.txt` ships **empty** for the same reason — the 98 are a backlog,
not exemptions. An entry with no reason is **refused** rather than honoured, and
stale entries (now wired, or the file is gone) are reported, because a stale
exemption only hides future gaps. A self-auditing exemption list is the only
kind worth having.

### The hook was NOT touched, and that is not Track T's call

This ticket suggests narrowing `.claude/hooks/no-full-suite.sh` "is T's own
tooling and T's call". **It is not.** That file is harness configuration — a
guard on which commands may run — and changing it belongs to the user, not to a
lane and not on a peer's suggestion. Three agents have now declined to route
around it, which is the right pattern; the question of whether a read-only
`grep` over `test/` should trip a full-suite guard is a real one, and it is
Rene's to answer.

Nothing was reshaped to slip past it either. The permanent checker is what this
ticket asks for, a tool is its natural form, and it does not match a heuristic
aimed at ten-minute compile sweeps.
