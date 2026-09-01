---
slug: decide-what-a-pin-means-and-what-may-block-one
track: U
type: decide
prio: 80
status: open
blocked-by: []
summary: "NOTHING IN THE TOOLING PREVENTS A PIN — verified, and this corrects the first version of this ticket. `would_pin` has ZERO deciding consumers (one assignment at twatch.py:2718, one comment); `pin_is_green` is used once, in cmd_pinstatus (trackt.py:1581), to name a ROLLBACK TARGET; and pin_shadow() says it 'deliberately never touches pinned, make pin, or stable_linux_amd64/**'. The code already implements the documented design. THE INVERSION IS IN READING: agents read 'would NOT pin' as 'cannot pin', and `make pin` — a ~34s human action needing only the self-host fixedpoint — was available every hour of the 49. The real cost is the RECOVERY leg, not the pin: pin_is_green needs a full run with no RED tier, nothing has qualified since v354 (2026-08-19), so the fast-pin trade's 'recovered, not prevented' has no fresh target. Owner (2026-09-01): 'a pin is a successful self compile... we added in all regression testing before we would do a full pin, but that is why we ran into this issue - no pin at all. which is a worse outcome.' The finding worth keeping is general: A SHADOW GATE THAT PUBLISHES A VERDICT NOBODY IS AUTHORISED TO ACT ON WILL BE READ AS AUTHORITY ANYWAY."
---

# What is a pin, and what is allowed to block one?

## CORRECTED 2026-09-01 — the code was never the problem

**The first version of this ticket said `would_pin`/`pin_is_green` had become a
precondition. That is false and it would have sent someone to "fix" correct
code.** Verified by grep:

| symbol | every non-test use |
| --- | --- |
| `would_pin` | `twatch.py:2718` assignment, `twatch.py:2654` comment. **Nothing reads it.** |
| `pin_is_green` | defined `trackt.py:1525`; used once at `:1581` inside `cmd_pinstatus`, to print *"last pin T found fully green"* — a **rollback target**. |
| `pin_shadow()` | docstring, `twatch.py:2628`: *"Deliberately never touches `pinned`, `make pin`, or `stable_linux_amd64/**`."* |

`pin_is_green` does not gate the pin; it **is** the recovery half of
"recovered, not prevented". Credit frank-T-on-seven for catching this, including
that it was the first to misread its own signal.

**So the inversion is in READING, not in code.** `make pin` is a ~34s human
action needing only the self-host fixedpoint, and it was available every hour of
those 49. What happened is that agents — this one included — read *"would NOT
pin"* as *"cannot pin"*.

**The general finding, which is worth more than any code change:**

> **A shadow gate that publishes a verdict nobody is authorised to act on will
> be read as authority anyway.**

That is a fact about advisory signals, not about pinning.

## The design, in the repo's own words

`devdocs/dev/track-t.md` states the design plainly:

> A pin is fast and unverified **on purpose**: `make stabilize-fast && make pin`
> is ~34s and proves the self-host fixedpoint, on the explicit trade that a bad
> pin is **recovered, not prevented**. Track A pays 34s instead of 25 minutes,
> and T supplies the verdict afterwards.

**A shadow gate that answers "would NOT pin" is preventing, not recovering.**
That is the whole issue. Nothing was designed wrong and nobody made a bad call;
a post-hoc verdict grew into a precondition, and each step looked like an
improvement.

## What it cost, measured 2026-09-01

| | |
| --- | --- |
| last pin | **v398, 2026-08-30 19:34** — 49h before this was written |
| pin cadence immediately before | **9 pins in 26h**, gaps of 0.7h to 7.9h |
| last pin T found FULLY GREEN | **v354, 2026-08-19** — 12 days |
| tree past the pin | **1724 commits**, 256 touching `compiler/` |
| `would_pin` outcomes today | every shadowed candidate: **would NOT pin** |

**The number that actually matters is the RECOVERY leg, not the pin count.**
"49h with no pin" is a human not running a 34s command. The real degradation is
that `pin_is_green` requires a `full` run with no RED tier, **nothing has
qualified since v354 on 2026-08-19**, so if v398 turns out bad the only
fully-verified target to recover to is twelve days stale. The fast-pin trade is
explicitly "a bad pin is recovered, not prevented" — and the recovery leg is the
half that quietly went missing.

The user-visible consequence: **the pin cannot build any C program for i386 or
arm32**, because the fix (`fc9c8ade2`) landed one day after v398. The tree
compiles C for all five targets; the pin compiles three. Tracks B/E build with
`$(PXX_STABLE)`, so for them the compiler is simply broken on two targets.

## The evidence that the blocking rule is not even self-consistent

`tools-devtest#00` has been red for 208 consecutive full runs — and it is in
v398's `pin_baseline`, so it is **waived**: `red_set - unexpected` resolves to
exactly `{tools-devtest#00}`. There were **81 `WOULD PIN` decisions with that
job red**. So the gate already tolerates an inherited red by design.

The streak did not decay, it **broke on one job**: `2026-08-31T05:36:03Z`, sha
`aac20e75ed1f`, *"1 red(s) the current pin does not have:
`test-pascal-conformance#shard0/6`"*. Sole blocker. `job_last_pass` for it is
`17fd5566a65e` — the last sha that would have pinned.

**One Track P parse regression has held the entire fleet's ground still for two
days.** That is the argument in one sentence.

## Owner's view, 2026-09-01

> *"a pin is a successful self compile. so, we added in all regression testing
> before we would do a full pin, but that is why we ran into this issue - no pin
> at all. which is a worse outcome."*

## Recommendation

1. **Say out loud that the pin gate is the self-host fixedpoint** — because the
   code already does this and the confusion was entirely in how the shadow's
   output reads. No tooling change is needed to cut a pin today.
2. **Make the shadow's output say what it is.** `would_pin: false` reads as a
   refusal. If it said *"advisory — 12 reds this pin does not have; pinning is
   not blocked"*, none of tonight happens. That is the one cheap code change and
   it is Track T's.
3. **Keep `pinstatus` and the green-fallback**, because "last pin T found fully
   green" is genuinely useful — it just must not be the thing that stops a pin
   being cut.

## The counter-argument, stated fairly

`pinned` is the ground B/C/D/E build every artifact on, and the reason pin
verification was built at all was that **18 of 25 pins never received a `full`
run and 13 were never judged in any tier**. Cutting fast pins again re-opens
that. The answer is that it was already the accepted trade — `make revert`
demotes a bad pin — and that 12 days of no movement is a larger, quieter cost
than an occasional bad pin that gets demoted. But it is a real trade and the
decision should name it rather than pretend the fast pin is free.
