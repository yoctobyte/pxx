---
slug: task-e-decompose-a-lekkerzeilen-roofs-frame-so-two-perf-tickets-stop-guessing-at-their-own-prize
title: "Decompose a lekkerzeilen ROOFS frame: what share is NilPy method dispatch"
type: task
track: E
prio: 45
status: new
created: 2026-09-22
found-by: frankh-c0
owner: ""
blocked-by: []
summary: "TWO PERF TICKETS ARE INDEPENDENTLY HELD ON THIS ONE ABSENT NUMBER AND NEITHER KNEW IT UNTIL A COORDINATOR NOTICED (2026-09-22). perf-o-the-variant-hidden-dest-clear (frankh-c0, p35) has deliberately deferred its timing half because its only cost evidence is synthetic, seven days old and measured against a binary that no longer exists; perf-a-every-return-releases-every-managed-local (frank-subcoord, p70) has independently refused to attach its measured 56.8% per-slot win to a frame, citing the size umbrella's do-not-multiply warning. Both need the same thing: NilPy method dispatch as a SHARE OF A REAL FRAME. THE MEASUREMENT HAS A HARD PRECONDITION -- the box must be QUIET, and that is a requirement rather than a preference, because the contention is DIFFERENTIAL between the arms: lekkerzeilen-7a measured the same binary, scene and pin at 530ms quiet against 624ms while peer sessions were merely COMPILING, with the CPython arm moving 66% against pxx's 18%, so a ratio taken on a loaded box is unbounded and interleaving does not rescue it. THREE THINGS THE REPORT MUST CARRY OR IT IS NOT QUOTABLE: the scene taken FROM THE INVOCATION and never from the banner (bug-e-every-world-reports-meta-name-rijn means world/roofs and world/rijn both print `rijn`), the `worldindex` rather than a tile count, and whether the box was quiet. AND THE DENOMINATOR IS THE TRAP: a variant carrier is minted PER CALL SITE, not per call (measured at HEAD, PXXDBG=a.ir, two k.m(t) sites mint two distinct unnamed carriers), so a per-slot win multiplied by call frequency mixes a per-site population with a per-call cost -- which is the umbrella's own do-not-multiply error arriving through a different subsystem. THE TWO CONSUMERS DO NOT SHARE A POPULATION and this ticket claimed they did for an hour -- retracted in the body: 8e's ~98% is tyAnsiString syms in compiler.pas (variants 3 of 23,693, 0.01%), while a NilPy program is SXR_STR 53.5%, variants 27.5%, records 16.4%, so the composition is a property of the FRONTEND and the carriers are a quarter of a NilPy program's sites rather than a share of 8e's number."
---

# Decompose a lekkerzeilen roofs frame

## Why this is a ticket and not a promise

frankz-e5 found that two perf tickets in the same subsystem were **both held,
correctly, on the same missing measurement, and neither seat knew about the
other.** I undertook to relay the result to `perf-a` when it arrived.

**That undertaking is the wrong instrument and this ticket replaces it.** A
promise lives in one session's context and does not survive a context boundary;
e5's own general form says it better — *"deferred pending X" creates no edge, so
the producer cannot see who is standing on the measurement and nobody is
notified when it lands.* An edge does survive. Both consumers should
`blocked-by` this, and then the machinery notifies instead of me remembering.

## PAUSED BY THE OWNER 2026-09-22 — NO DATE, AND THAT IS THE POINT

*"ok. stop gui testing lekkerzeilen for a while please"* (owner, relayed by
`frankuser`). `lekkerzeilen-7a` was mid-run on the roofs pair and has stopped.

**So this row is not blocked on a seat and not on a quiet box — it is blocked on
him lifting a pause, and he gave no duration.** Anyone opening this should read
it as WAITING WITHOUT A DATE, not as imminent. Both consumers have been released
rather than held: `perf-o` is parked and unowned, and its `blocked-by` edge to
this ticket survives, which is what makes releasing safe.

**Scope, deliberately not widened:** he named GUI testing of lekkerzeilen. That
is not compile-time work, not other demos, and not non-GUI lekkerzeilen work.
Nobody should extend it on his behalf — ask him.

**What is already banked and does NOT need the display**, so a later seat does
not re-derive it: both arms built and verified; the dispatch/variant-arithmetic
bucket split by symbol family (`PyHostCall`, `PyFindMethCI`, `PyFieldGet/Set`,
`PyBindHostKwArgs`, closure arm against `PXXVarBinOp*` and pyeval's integer fast
paths); the stamp fields (`region` from the invocation, `worldindex` as a sha,
`tiles`/`twins`, per-round `loadstart`/`loadend`); and 7a's two-rounds-per-arm
repeatability falsifier, declared in advance.

## What to measure

NilPy method dispatch as a **share of a roofs frame**, on a quiet box.

`lekkerzeilen-7a` has been asked for this and is the natural owner: it holds
the scene, and it is correctly not taking the display while the box is
contended. It is not assigned here.

## The preconditions, and why each one exists

- **A quiet box — BUT SCOPED CORRECTLY, AND I HAD IT TOO STRONG.** Corrected
  2026-09-22 by `lekkerzeilen-7a`, whose numbers I derived it from in the first
  place. The 530 ms / 624 ms evidence is an **fps RATIO between two
  implementations with different load sensitivity** (CPython moving 66% against
  pxx's 18%), and a ratio like that is unbounded on a busy box. **A
  decomposition is not that measurement.** Shares are computed WITHIN a single
  run, so a uniformly slower box moves every bucket alike and the shares
  survive. What load can still do is inflate GPU-wait and scheduler time into
  the library bucket — real, and bounded.
  So the gate 7a actually runs is `load < 2.5` with a twelve-minute cap,
  stamping `PROCEEDING UNSETTLED` with the measured load beside every row rather
  than blocking forever. **That is the right call and this ticket should not have
  implied otherwise:** a row with its load attached is quotable, and lets each
  consumer discount it themselves instead of having the producer decide. I had
  carried a precondition from the measurement it was derived from to a different
  measurement, which is the "a claim scopes to exactly what was checked" rule
  applied to a PRECONDITION rather than to a result.
- **Scene from the invocation, never the banner.**
  `bug-e-every-world-reports-meta-name-rijn` — `world/roofs` and `world/rijn`
  both print `rijn`, so a banner-sourced scene label is unfalsifiable.
- **`worldindex`, not a tile count.**
- **Say whether the box was quiet**, so a later reader can tell a clean row
  from a contended one rather than assuming.

## The denominator trap, stated once so both consumers inherit it

A variant carrier is minted **per call SITE**, not per call — measured at HEAD
with `PXXDBG=a.ir`: two `k.m(t)` sites mint two distinct unnamed carriers. So a
release sweep's population is per-site while the dynamic cost is per-call.
**Multiplying a per-slot win by call frequency mixes the two.**

### RETRACTED WITHIN THE HOUR: the two tickets do NOT share a population

This section originally ended *"both tickets this unblocks are about variant
carrier slots and the two numbers read as interchangeable."* That was mine and
it was wrong. frankb-8e censused release sites by arm at HEAD (`c09551004`):
its ~98% is `ParseFactorCore` in `compiler.pas` — 10 named against 609 unnamed
**tk 23 = tyAnsiString** syms — where variants are **3 sites of 23,693,
0.01%**. My carriers are not inside its number.

I had verified MY end (NilPy call sites mint nameless carriers, per site) and
stated a claim about the **intersection**. Recorded because the per-site fact
was correct and was doing credibility work for an overlap claim it did not
support.

**What is true instead is more useful, and it is a property of the FRONTEND
rather than of the mechanism:**

| program | SXR_STR | variants | records |
| --- | --- | --- | --- |
| `compiler.pas` | 23,531 (99.3%) | 3 | 23 |
| NilPy with calls | 2,387 (53.5%) | 1,229 (27.5%) | 731 (16.4%) |

So the carriers are about **a quarter of a NilPy program's release sites**, and
the umbrella's target program runs under nilpy — which is why that is
load-bearing rather than a curiosity. These remain SITE counts and say nothing
about per-call cost.

The per-site/per-call trap above stands on its own and never depended on the
retracted overlap.

**And the instrument note that goes with those numbers, because they are not
quotable without it:** 8e's first census answered `PXXVarClear` 58.6% against
`PXXStrDecRef` 0.9% — "a NilPy sweep is mostly variants", which was the
hypothesis it had been handed. The x86-64 string arm does not call
`PXXStrDecRef`; it calls `AnsiStrReleaseAddr`, a compiler-emitted blob with
**no symbol**, so a name-based census saw 18 unrelated direct calls and missed
all 2,387, and the silence read as zero. **A census enumerating call targets by
NAME is silent about anything nameless**, which in this subsystem is precisely
the blob arms. The corrected figures above came from a byte signature with a
clean negative control.

## What would retire this

A single row, with its preconditions stated, in both consuming tickets.
