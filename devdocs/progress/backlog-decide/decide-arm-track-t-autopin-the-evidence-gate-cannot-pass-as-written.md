---
slug: decide-arm-track-t-autopin-the-evidence-gate-cannot-pass-as-written
track: U
prio: 90
type: decide
status: backlog
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
