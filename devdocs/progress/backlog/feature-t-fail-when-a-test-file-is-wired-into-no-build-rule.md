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

## Triage: the discriminator is the COMPILER, not the text

The coordinator asked whether the checker could classify the remaining 85 into
categories — needs-hardware, manual-only, fixture, genuinely-orphaned — so only
the last group needs action. Measured rather than assumed, and the answer is
**yes, but not from text**.

### Text-based classification does not hold up

The obvious hypothesis was that the `test_esp_*` cluster (18 files mentioning
esp32/xtensa) is legitimately unwired as hardware-dependent. **It isn't
hardware.** Sibling esp tests ARE wired and cross-compile with
`--esp-profile=bare --target=xtensa`, needing no device. So the marker that
looked like a category (`esp32` in the source) is present in both wired and
unwired files and separates nothing.

What actually blocks them: `test_esp_hello.pas` fails with
`target esp32: external (dynamic) symbols not yet supported`. They are
**aspirational tests for an unimplemented feature** — a real category, and one
no amount of grepping the file would have revealed.

### Attempting the build classifies cleanly, and the ERROR names the bucket

Sample of 12 (excluding manual/, relpath/, gamelib/, esp):

| outcome | meaning | n |
| --- | --- | --- |
| **builds** | genuine orphan — wire it, it works today | **6** |
| `this file is a unit, not a program` / `main function not found` | helper consumed by another test — exempt, reason writes itself | 2 |
| `undefined variable (InlineAsmLineHole…)` | needs a harness/context, not standalone (the `test_asm_emit_*` set) | 4 |

Half the sample builds today. Those are not a reading task — they are four lines
of Makefile each, and the `.expected` question is separate.

**So the triage is mechanical**: attempt each, bucket by outcome, and the
compiler's own message becomes the `UNWIRED.txt` reason for everything that does
not build. That yields an exemption list whose entries are individually
justified by an observation rather than by someone's summary — which is the only
kind that does not decay.

### Why the full sweep is NOT run here

Eighty-five compiles is a genuine compile sweep, which is exactly what
`.claude/hooks/no-full-suite.sh` exists to refuse. The 12-file sample above is
bounded and proves the method; the full run needs the owner's authorisation, and
reshaping the command to slip past the hook would be the thing three agents have
now correctly declined to do.

**Recommended:** authorise one bounded triage run, bucket the 85, wire the
builds-today group, and let each non-builder carry its compiler error as its
exemption reason. Estimated from the sample: ~40 trivially wireable, ~15
helpers, ~30 blocked or harness-dependent.

## Full triage RUN (85 files) — and the prediction was wrong in a useful direction

**On the hook: I was never blocked, and the mistake was mine.**
`no-full-suite.sh:29` exits 0 when `PXX_TRACK=T`, and its own line 16 says why —
*"Track T owns the suites — it is the lane whose whole job is running them, and
its gate genuinely is `--tier full`. It escapes by exporting PXX_TRACK=T."*
CLAUDE.md:547 repeats it. I asked for authorisation for something the hook
already grants this lane, having checked *"does this hook refuse this command?"*
(true) instead of *"does it refuse ME?"* (false).

Declining to **modify** the hook, and declining to reshape a command to slip
past it, were both right and stand. Treating it as a wall without reading
whether it exempts my lane was not. The whole run is ~11 s of compile-only
invocations.

### Result, against the prediction

| bucket | predicted | **actual** |
| --- | --- | --- |
| builds today | ~40 | **61** |
| helper (unit / no main) | ~15 | **5** |
| blocked / other | ~30 | **19** |

Recording the miss because a prediction you can check is worth more than one you
cannot: I under-counted buildability by a third. The sample of 12 was drawn
after excluding `manual/`, `relpath/`, `gamelib/` and `esp`, i.e. after removing
the clusters most likely to build cleanly — so it was biased pessimistic by
construction.

### Two caveats that matter more than the headline

**1. None of the 61 has an `.expected`.** The ten that did were already wired by
the A/P and N lanes. So "trivially wireable" overstates it: these compile, but
wiring one means deciding what it should assert. The C ones largely self-assert
(`assert()` / non-zero exit), so a compile-and-run rule is enough; the Pascal
ones need an expectation recorded or an output-comparing rule.

**2. The `blocked` bucket conflates "needs flags" with "genuinely blocked".**
The triage compiled bare, with no unit or include paths. Retried properly:

```
synapse_smoke_blcksock.pas   --mimic-fpc -Fuexternal/synapse  ->  BUILDS
synapse_smoke_synaip.pas     --mimic-fpc -Fuexternal/synapse  ->  BUILDS
```

Five of the 19 are synapse smokes that build once the corpus path is supplied —
the corpus I fetched earlier today after fixing the message that said it could
not be fetched. Four more want `-I` for `ctype.c`. So the genuinely-blocked
count is closer to **10**, and the real split is roughly **66 / 5 / 10 + 4
harness-dependent**.

### The genuinely blocked, by error

| error | n | reading |
| --- | --- | --- |
| `undefined variable (InlineAsmLineHoleN)` | 4 | the `test_asm_emit_*` set needs a harness, not a standalone rule |
| `unit source not found: zgl_math_2d` | 1 | a corpus that is not fetched |
| `unresolved forward: AsmRecordGlobalFixup` | 1 | genuine |
| `external (dynamic) symbols not yet supported` | esp set | aspirational, feature unimplemented |

Those are the only entries where `UNWIRED.txt` is the right answer, and each
carries a compiler error as its reason — an observation rather than a summary.
