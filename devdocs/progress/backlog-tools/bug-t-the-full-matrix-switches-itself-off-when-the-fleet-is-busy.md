---
slug: bug-t-the-full-matrix-switches-itself-off-when-the-fleet-is-busy
type: bug
track: T
prio: 60
status: open
owner: frankH
---

## summary

**A NEW PIN STOPS THE FULL TIER, because `pin-verify` sits above platform
breadth in the idle ladder and cannot finish while pushes arrive.** Fleet push
rate is a contributing factor, not the cause.

**CORRECTED TWICE, 2026-09-06.** The first two versions of this ticket named the
push rate as the mechanism. Both were wrong, and the history is kept below
because the way it was wrong is more useful than the fix.

## the cause, from published state

Last full published **18:37:24Z**. Pin v406 committed **18:42:14Z**. Five
minutes apart, and `tstate/seven.json` says why:

```
idle_yield        {"aborts": 2, "phase": "pin-verify", "target": "1b903c1dd..."}
pin_verify        {"date": "2026-09-06T08:19:39Z", "sha": "36eb642d6240..."}  <- still v405's
last_breadth_try  {"date": "2026-09-05T21:51:18Z"}                            <- 21h ago
```

A new pin mints a new pin-verify target. `pin-verify` is a HIGHER idle phase
than platform breadth (the `elif pin_mid ...` arm precedes the breadth arm; only
the request queue is above it). It has held the idle slot since 18:42Z, is
preempted before its `full_commit_secs` commitment point, and at `aborts: 2`
against `IDLE_YIELD_AFTER = 3` has not yet yielded even one slot downward. It
has also never verified v406 — `pin_verify` still names v405's sha.

**twatch.py predicted this in its own comment**, which is better evidence than
any reasoning here: *"Measured on seven 2026-08-29: 7 pin-verify attempts, 7
preemptions, 0 completions... IDLE_YIELD_AFTER bounds the damage to other phases
but does nothing for the pin: yielding the slot is not the same as ever
verifying."*

So the push rate matters — it is what stops pin-verify finishing — but the
EVENT that changed at 18:37Z was the pin, and a rate cannot explain a sharp
edge.

## the escape hatches, and their order

Idle phases run: **requests -> pin-verify -> breadth**.

- `breadth_overdue()` reserves a slot ahead of the fast verdict with
  `commit_after=0`, so nothing can abort it. It arms only when `last_full` is
  stale past `breadth_stale_secs()`, **6h by default** — from an 18:37Z full
  that is ~00:37Z. Waiting does not work on a timescale anyone wanted.
- The **request queue** (`--request <sha> --request-tier full`) is above
  pin-verify, so it bypasses this entirely. It still needs
  `full_commit_secs` of no testable push to commit. **Hold plus request works;
  hold alone does not.**

## not measured

`breadth_stale_secs` and `full_commit_secs` come from `twatch.conf` in seven's
clone, unreadable from plexus; the numbers above are the shipped defaults.
Whether the full rung was ENTERED during any slot pin-verify yielded is not in
published state — `last_breadth_try` covers only the reservation path, which
provably has not fired since 2026-09-05. **That question is open** and the
daemon's stdout on seven settles it.

## the two wrong versions, kept because the shape repeats

**v1 — wrong population.** "One push per 60s", counting ALL commits.
`needs_test()` returns False for a commit whose every path is under
`NOTEST_PREFIXES = ("devdocs/", "docs/")`; 50 of 69 commits after 18:37Z were
docs-only, so 72% of the traffic cannot abort anything. The raw-commit
correlation was real and fitted the outage perfectly — and it fitted because
docs traffic and code traffic come from the same seats and move together.
**A correlation measured over a superset tracks the subset whenever the two move
together**, so the check must be against what the code counts, never against the
quality of the fit.

**v2 — right population, missing term, and still the wrong cause.** Corrected to
testable commits, then added that the box is not idle while the ~170s native
verdict runs, so the requirement is `native_wall + full_commit_secs` ~= 230s:
of 18 testable gaps, 11 exceed 60s and only 2 exceed 230s. All true, and it
still named a rate rather than the pin.

**v2 also "refuted" the right answer.** It was proposed that the ladder never
REACHES the full rung. `idle_phase` returns `mid_tier` on its first rung and the
shipped default collapses `mid == deep == "full"`, so the rung IS immediate —
correct, and beside the point: `idle_phase` is only consulted after the higher
`elif` arms decline, and pin-verify is one of those. **Verifying the predicate
and never checking how it is applied**, which is the same error frankuser made
on `NOTEST_PREFIXES` the same hour, one layer out.

