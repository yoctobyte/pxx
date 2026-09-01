---
slug: umbrella-one-full-tier-run-with-no-red-tier
track: T
prio: 85
type: umbrella
blocked-by: [regression-lib-test-crtl-reachability-7, regression-test-core-c-crtl-enosys-stubs, regression-test-core-test-header-static-body, regression-test-core-test-interface-byval-param-no-leak, regression-test-core-test-rtl-fpc-compat-helpers-2, regression-test-core-test-thread-api-no-uses, regression-test-threads-test-exception-threads-race, regression-test-threads-test-threadsafe-refcount-lockfree, regression-test-xtensa-test-signal-default-revert-b336, regression-test-xtensa-test-signal-handler-callback-b336, regression-tools-devtest-00-3, regression-optdiff-shard4-12, bug-a-dce-miscompiles-every-threaded-program-and-o3-turns-it-on, bug-t-optdiff-cannot-see-any-threading-program-since-the-threadsafe-directive-became-an-error]
created: 2026-09-01
owner: frankZ
summary: "GOAL, not a unit of work: one `full` tier run with no RED in any tier judged at that sha. That is what grades a pin `green` rather than `reds(N)`, and no PINNED sha has earned it since v354 on 2026-08-19. A pin is neither blocked nor gated by this — CLAUDE.md now says a valid pin IS the self-host fixedpoint and nothing else may block one, and rollback falls back to the most recent pin, so recovery is never empty. What a green run buys is a rollback target that is VERIFIED rather than merely recent. The umbrella ENDS when one such run comes back; it is not a standing triage desk."
---

# One full tier run with no RED tier

Written 2026-09-01 by frankZ, from the owner's words via frank-user: *"we
should have one track working on the regressions, and only the regressions."*

## What this buys, stated accurately

The original framing for this umbrella was that the pin's recovery leg was
*dead*. That was too strong and CLAUDE.md has since settled it: **a valid pin
is the self-host fixedpoint and nothing else may block one** (owner,
2026-09-01), pins are GRADED (`green`, or `reds(N)` with the manifest) rather
than gated, and rollback *"prefers a green pin and falls back to the most
recent, so recovery is never empty."*

So nothing is blocked and nothing is empty. What a green run actually buys is
that the rollback target becomes **verified** instead of merely **recent** —
the difference between falling back to a pin known to be sound and falling
back to the last one taken. v398 is the argument for the distinction: it
shipped a compiler that could not build C for i386 or arm32, and every
`$(PXX_STABLE)` consumer carried that for two days.

Worth having. Not an emergency, and this ticket should not be quoted as one.

## What "green" actually means here, measured

`tools/trackt.py:1525`:

```pascal
def pin_is_green(runs_for_sha):
    """Judged by T, with a `full` run, and nothing RED in any tier judged."""
```

Two conditions, and the second is the one that surprises people: **every tier
judged at that sha must be GREEN, not just `full`.** `opt` is disjoint from the
quick<native<limited<full chain and runs only as idle watcher work — but it
co-occurs with `full` on **704 of the 1234 shas that have ever had a full
run**, so a red `opt` tier does count against roughly half the candidates.
`optdiff` lives in `opt`; that is why it is wired here.

Also measured, because the two get conflated: **588 shas have been fully green
at some point, the most recent `90892318c94c` on 2026-08-26.** The twelve-day
figure is about *pinned* shas, which is a strictly smaller set. Fixing the reds
is necessary; it is not sufficient, because the pin also has to be verified at
a sha that carries the run.

## How this umbrella grows — attempt, do not triage

Run the tier. Every RED it returns names a ticket, in the order it actually
costs. Nothing gets wired here because it looked related.

**Re-lane before working.** An auto-filed regression carries `track: T` (or a
track guessed from the failing STEP) as a FALLBACK, not a finding, at a prio
nobody set. T owns the TOOL, never the BUG. Thirteen of these accumulated with
nobody on them for exactly that reason.

## The groups, from the 2026-09-01 sweep

Report by group. A count of tickets is not a count of causes.

1. **`-O3` DCE miscompiles every threaded program** — five optdiff shards, one
   bug. [[bug-a-dce-miscompiles-every-threaded-program-and-o3-turns-it-on]].
   Currently MASKED: those programs no longer compile under optdiff, so the
   shards will report green while the miscompile is live —
   [[bug-t-optdiff-cannot-see-any-threading-program-since-the-threadsafe-directive-became-an-error]]
   is the other half and must land, even though a correct optdiff is red until
   the DCE bug is fixed.
2. **Threading correctness in the RTL** — `test_threadsafe_refcount_lockfree`,
   `test_exception_threads_race`, `test_thread_api_no_uses`. Distinct from
   group 1: these are red at the default `-O`, with no DCE anywhere near them.
3. **crtl / C headers** — `crtl_reachability` (a `clock_t` stray token in
   `lib/crtl/src/sys/time.c` reached through the PINNED compiler, so this one
   is pin lag as much as a source bug), `c_crtl_enosys_stubs`,
   `test_header_static_body`.
4. **xtensa PAL** — both b336 signal tests, one error:
   `undefined variable (PAL_ERR_UNSUPPORTED)`.
5. **Managed memory** — `test_interface_byval_param_no_leak` (24/25),
   `test_rtl_fpc_compat_helpers` (segfault).
6. **`optdiff#shard4`** — a NAME COLLISION with group 1, not a member of it:
   output divergence (`rc 0 vs 0`) rather than a timeout, fires at -O1/-O2/-O3
   rather than -O3 only, and its last pass is two days older. Already ticketed.
7. **`tools-devtest#00`.**

## The count is not falling on its own

Native reds on seven went **2 → 7 between 19:13Z and 20:11Z on 2026-09-01**,
from ordinary lane work landing. That is the standing condition this umbrella
is measured against: the target is not "fix thirteen things", it is "get one
run where the arrival rate loses to the fix rate for one tier's duration."

## Do not

- **Never `make pin`.** Irreversible, and the owner's alone.
- Do not widen this into a triage desk. One clean run and it closes.
- Do not read a shrinking red count as progress without checking whether the
  job still RUNS. Group 1 is exactly that failure mode.
