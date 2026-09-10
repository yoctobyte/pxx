---
slug: decide-arm-track-t-autopin-the-evidence-gate-cannot-pass-as-written
track: U
prio: 90
type: decide
status: decided
owner: ""
created: 2026-09-09
found-by: frankuser
tags: [pin, track-t, autopin, workflow, owner-blocker]
blocked-by: []
summary: "The owner designed Track T auto-pin on 2026-08-08 (option A: baseline allowlist, K>=2 consecutive qualifying shas, auto-rollback) and it was built and started in SHADOW MODE, to be armed once its calls could be compared against what a human actually blessed. Measured 2026-09-09: the machinery has worked correctly for a month -- 123 WOULD PIN verdicts, 57 of them at ZERO reds, most recently 2026-09-07T21:01Z -- and has never been armed, because THE COMPARISON THAT WOULD ARM IT CANNOT BE RUN. The shadow evaluated 647 of 13,938 commits (4.6%); humans pin at whatever HEAD is when they decide. Overlap between 94 human pins and 123 shadow-cleared shas is ZERO against ~4 expected by chance. The two processes sample disjoint sets of shas, so 'compare a week of shadow verdicts against human pins' is unsatisfiable AT THE SHA LEVEL. This is a gate that cannot pass, and it has held the fleet's only automated pin path for a month."
---

# Why this is prio 90 and addressed to the owner

He said it himself, 2026-09-09: *"the idea initially was that track T would pin
if all tests run green."* It does that. It has done it 123 times. Nothing
consumes the answer.

This ticket is not "auto-pin is unimplemented". It is **implemented, running, and
correct**, and it is parked behind an evidence gate that no amount of waiting can
satisfy. That distinction is the whole finding: a month of stasis reads as
neglect or as instability, and it was neither.

# Measured 2026-09-09

| | |
| --- | --- |
| shadow log span | 2026-08-09 -> 2026-09-08, 647 verdicts over 30 days |
| **WOULD PIN** | **123** |
| of those, at ZERO reds | **57** |
| would-pin PENDING (qualifying, awaiting the K>=2 streak) | 30 |
| would NOT pin | 494 |
| pins a human actually ran in the same window | 94 |
| **shas in common between the two sets** | **0** (≈4 expected by chance) |

`tools/twatch.py` already computes the decision in full:

```python
qualifies = not unexpected and selfhost_ok
streak    = (prev_streak + 1) if qualifies else 0
would     = qualifies and streak >= PIN_STREAK_K
```

`PIN_STREAK_K = 2`, `PIN_TIER = "full"`, and the self-host check is deliberately
unwaivable — *"a compiler that cannot reproduce itself must not become anyone's
ground, allowlist or not"*, asked of THIS RUN so history cannot poison it. The
allowlist is currently **empty**, so nothing is waived at all today.

**The only missing piece is that `would == True` writes a log line instead of
running the pin.**

# The gate that cannot pass

The code comment states the arming condition: shadow *"records the decision it
WOULD have made so a week of them can be compared against what a human actually
blessed — evidence instead of argument."*

That comparison is unrunnable as specified. The watcher samples ~4.6% of commits;
a human pins at HEAD at the moment they choose to. The sets do not intersect, and
a month produced zero overlapping shas. **Waiting longer produces more shadow
verdicts and still no comparison** — which is exactly why nothing changed for a
month while everyone believed evidence was accumulating.

CLAUDE.md already names this class: *"a gate that cannot pass is not a gate
either."* It was written about test guards. This is the same animal governing the
fleet's ground.

# The fork

**A. Arm it as designed** — `would_pin` drives `make pin`. Allowlist stays empty,
so it fires only on a full tier with no unexpected red AND a live passing
self-host job, twice consecutively. That is a strictly higher bar than the pins
being taken by hand today: v407 went out graded *"quick GREEN, full tier NOT
RUN"*.

**B. Replace the unsatisfiable comparison with one that can run**, then arm.
Do not compare shas; compare CLAIMS. For each WOULD PIN, ask whether the tree was
in fact good — the tier rows at that sha already answer it, and 57 zero-red
verdicts is that evidence. Cost: an afternoon, and it delays arming again.

**C. Leave it in shadow.** Then the pin path stays human-only and the complaint
that produced this ticket stays true.

# Recommendation

**A.** The bar is already higher than current practice, the self-host property
that actually defines a pin is unwaivable and checked per-run, and K>=2 plus an
empty allowlist means it refuses far more often than it fires (494 refusals to
123 clears). B's evidence is worth having but it is a reason to arm *and then*
measure, not to wait again — the last month is what waiting costs.

**Not actioned by this seat.** Arming auto-pin is arming an irreversible,
outward-facing action, and `make pin` is the owner's alone. This is written so
the answer can be one word.

## ANSWERED BY THE OWNER ON 2026-09-09 — AND THIS TICKET SAT OPEN AT PRIO 90 FOR TWO DAYS AFTER

Measured 2026-09-11 by the seat that filed it (frankuser). `devdocs/progress/tstate/pin-armed`
on origin/master:

> Track T automatic pinning is ARMED.
> Armed 2026-09-09 by the owner: *"go ahead and arm it."*

Option **A**, as recommended. The switch is the committed file itself
(`fc2ce3d02`); its presence arms, deleting it returns the watcher to shadow mode
with no code change.

**So this ticket was CLOSED BY EVENTS and stayed at prio 90 in a ranker for two
days, asking him to decide something he had already decided.** That is the exact
shape the owner described on 2026-09-10 about a `math.atan2` ticket found closed
26 days earlier — *"agentic coding has an ADHD disorder ... you dive into
anything that grabbed your attention. and forget about the bigger goal."* This
one is worse in one respect and better in another: worse because the seat that
filed it is the owner-facing seat and had the answer in its own session's reach
the whole time; better because it was two days, not 26.

Two corrections to the body above, for anyone reading the history:

- *"The allowlist is currently empty, so nothing is waived at all today"* — it now
  carries **two** entries, both ticketed as the design requires
  (`test-duktape#00`, `test-quickjs#00`).
- The arming condition turned out not to need the unsatisfiable comparison at all.
  He simply decided. Which is its own lesson about escalating a blocked gate
  rather than waiting on it: the gate was unsatisfiable, and the cost of saying so
  was one sentence.

**RESIDUAL, AND IT IS LIVE: ARMED IS NOT PINNING.** Filed separately as
`bug-t-armed-autopin-has-refused-62-consecutive-times-and-the-tree-has-had-no-pin-for-99-hours`,
because "the decision was taken" and "the decision had an effect" are different
claims and only the first one is closed here.

## Log
- 2026-09-11 — decided; this names the commit that carried the decision, which is not always the one that carried the change — commit 945d6c3de.
