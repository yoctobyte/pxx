---
slug: decide-what-a-pin-means-and-what-may-block-one
track: U
type: decide
prio: 80
status: open
blocked-by: []
summary: "The pin gate INVERTED and nobody noticed. devdocs/dev/track-t.md says a pin is fast and unverified ON PURPOSE — a self-host fixedpoint, with a bad pin 'recovered, not prevented' and T supplying the verdict afterwards. But `would_pin`/`pin_is_green` became a PRECONDITION: seven's shadow answers 'would NOT pin' and no pin is cut. Measured cost: 49h with no pin, last fully-green pin v354 from 2026-08-19 (12 days), tree 1724 commits and 256 compiler/ commits past the pin, and Tracks B/C/D/E building C for i386/arm32 against a binary that cannot. Owner's view (2026-09-01): 'a pin is a successful self compile... we added in all regression testing before we would do a full pin, but that is why we ran into this issue - no pin at all. which is a worse outcome.' Recommendation: restore the documented design — fixedpoint gates the pin, regressions are a post-hoc verdict — and keep the shadow as ADVICE."
---

# What is a pin, and what is allowed to block one?

## The inversion, in the repo's own words

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

1. **The pin gate is the self-host fixedpoint.** Restore what track-t.md already
   says. `make stabilize-fast && make pin`, ~35s, and it is Track A's operation.
2. **Regression state is a post-hoc VERDICT, not a precondition.** T keeps
   shadowing and keeps publishing `would_pin` — as **advice**, and as the input
   to `make revert`. Recovered, not prevented.
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
