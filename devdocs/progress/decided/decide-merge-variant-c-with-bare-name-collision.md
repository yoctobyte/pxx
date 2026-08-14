---
track: U
prio: 75
type: decide
blocked-by: []
summary: "Variant C (sibling Exception classes) is BUILT and GREEN on wip/exception-sibling-design. Merging it makes both sysutils and pylib export a class named `Exception`, and pxx resolves such a collision to the FIRST unit named where FPC resolves it to the LAST. Ship now and accept a backwards bare-name answer for programs using both units, ship behind the parity fix, or change the tests' contract. Recommendation inside."
status: decided
---

# Merge variant C now, or wait for uses-clause last-wins?

The work in [[feature-a-one-exception-class-in-a-shared-unit]] is finished and
measured — `gate.sh quick` GREEN, self-host converges, both uses orders produce
identical output, the four NilPy exception tests pass, and
`bug-nilpy-exception-repr-and-type-name-say-pyexception` is fixed by
construction. It is on `wip/exception-sibling-design`; master is untouched.

One question is left and it is a judgment call, not a bug to chase.

## The fork

Merging makes **two** units export a class named `Exception` (siblings under a
shared `ExceptionBase` — that IS the design). Qualified references now resolve
correctly in every position, which is the work that unblocked this.

The BARE name under a collision does not, and the reason is general:

| | bare `Exception` under `uses pylib, sysutils` |
| --- | --- |
| FPC (measured against the oracle) | **sysutils'** — the LAST unit named wins |
| pxx today | **pylib's** — the first registered wins |

That is [[bug-pascal-uses-clause-duplicate-name-resolves-first-not-last]], filed
separately because it is far wider than exceptions: it applies to any name two
used units share — type, routine, constant — and it is silent.

Today it is invisible, because the RTL has no duplicated names. **Merging
variant C is what makes it reachable.**

## Options

**A — merge now, accept the backwards bare name.** Programs that use BOTH
`pylib` and `sysutils` and write bare `Exception` get pylib's class. In
practice that is NilPy-runtime-plus-RTL programs, i.e. approximately the two
regression tests. Everything else is unaffected, and every program can say what
it means today by qualifying.

**B — fix last-wins first, then merge.** Correct order, and the bare name is
then right by FPC's own rule with no accommodation anywhere. Cost: last-wins is
a resolution-order change in shared Track A ground with a whole-suite blast
radius, and it blocks a finished, green feature behind an unstarted one.

**C — merge, and make a bare collision a DIAGNOSTIC** rather than a silent
pick (error, or a warning under `--strict-uses`). Loud instead of backwards. It
does not implement FPC's rule, so it is a deviation of a different kind — but a
deviation that cannot silently run the wrong body, which is the failure mode
this repo has paid the most for.

## Recommendation: A, then B, and treat C as part of B

Merge now. The feature is green and it retires three mechanisms (the catch
bridge, the `msg`-must-be-first layout contract, the pylexer rename). The
exposure is narrow and always avoidable by qualifying, and the parity ticket is
filed with a measured oracle repro, so nothing is being lost track of. When
last-wins lands, add the diagnostic with it and let the tests assert the bare
name again.

Option B is the tidier order and I am not recommending it only because it
parks finished work behind a resolution-order change nobody has scoped.

## What merging involves (whichever option wins)

**The re-pin is part of the landing, not a follow-up.** `sysutils` now
`uses exceptions`, a `compiler/builtin/` unit the PINNED compiler does not have,
and Track B builds `lib/**` with `$(PXX_STABLE)`. The merge and
`make stabilize-fast && make pin` must land together or every Track B build
fails on an unknown unit. `gate.sh quick` cannot see that — it is the
[[feedback_lib_rtl_cannot_call_a_head_only_builtin_method]] shape.

## Also decide, cheaply

`test_uses_order_pylib_exception_a/_b` were rewritten on the branch to assert
the QUALIFIED property (each unit's surface reachable in either order) and to
stop asserting the bare one. That is this ticket's prescription from an earlier
session and it is a real property now rather than an accommodation — but it does
mean the pair no longer guards the bare name at all until last-wins lands.
Confirm that is wanted.

## DECIDED 2026-08-14 by the user — option A, merge now

**The exposed case is synthetic.** The bare-name collision is only reachable
from a program that imports BOTH `pylib` and `sysutils`. In the user's words:
that is not any standard Python program, and there should never be a need for
it — Python has its own libraries. The two regression tests that exercise it are
constructed to exercise it; no real program is in that position.

> *"We are now crafting our own problem out of a sort of fetishism. This is not
> what cross importing was intended for."*

So: **merge**, accept the bare-name answer, and let
[[bug-pascal-uses-clause-duplicate-name-resolves-first-not-last]] carry the
parity fix on its own schedule. Not option C — a diagnostic for a case nobody
reaches is noise with a maintenance cost.

### What cross-import is actually for (scope statement, worth keeping)

The intended use is **Python importing C libraries** — `import sqlite.c`, and
compiling SQLite in statically. Each frontend has its own runtime library:
Python has one, C has one, Pascal has one. Cross-import exists so a program can
reach the *other language's* real libraries, not so a `.npy` can pull Pascal's
RTL. Pascal forms and the rest of the RTL are explicitly not on the menu.

That bounds this whole class of problem: a `.npy` reaching `sysutils` is outside
what the feature is for, which is why its collision does not deserve a
resolution-order redesign.

### Options left open, deliberately

Two cheaper fixes exist if the case ever stops being synthetic, and either can
land later without redoing this:

1. **Reorder the built-in units' `uses` when both are pulled** — a targeted
   cheat, one call site.
2. **Refuse Pascal RTL units from a `.npy` outright** — "unit not available from
   Python". Arguably the honest expression of the scope statement above, and it
   turns a silent wrong-class into a compile error naming the real rule.

Neither is needed to merge, and the user's instruction is explicit: pick the one
that makes sense, and change it later if it matters.

### Per-frontend reading (why the bare name is not "backwards" for NilPy)

The 2026-08-13 governing rule already covers this: the default follows the
reference implementation **per frontend** — CPython for `.npy`, FPC for `.pas`.
Under that rule pxx's current answer is *correct* for a `.npy` (pylib is the
Python library, so it wins) and wrong only for a `.pas`. The parity ticket is
therefore narrower than it reads: it is about applying FPC's rule in Pascal, not
about collisions in general.

## Log
- 2026-08-14 — decided, commit PENDING-COMMIT.
