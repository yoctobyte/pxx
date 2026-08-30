---
track: U
prio: 50
type: decide
status: backlog
owner: unassigned
blocked-by: []
summary: "tools/exit_observable_devtest.py fails when the count of stdout-only cross-target rows exceeds a high-water mark. AMENDED 2026-08-30 by frankT (904b26bd9) AND THE AMENDMENT CUTS AGAINST THE ORIGINAL RECOMMENDATION -- read the addendum before deciding. The filing measured 531 -> 551 in six hours from three lanes' normal work and leaned toward option 3 (report the drift, stop failing) on the grounds that a standing red nobody owns is the state a red exists to prevent. Re-measured per Makefile commit, the count peaked at 559 and then a lane paid it back to 531 EXACTLY within six hours (d9d166f7e, Track A; bug-a-twenty-new-cross-target-rows-compare-stdout-without-the-exit-code is in done/). So the red WAS owned and paid, and the ratchet is what applied the pressure. RESIDUAL NOW CLOSED (7d1f9aeb4, A+S, 21:58): the 2 xtensa exception/unwind rows assert the exit code on both sides, the count is back to the 531 mark and tools/exit_observable_devtest.py is GREEN -- so the ratchet has now been paid down twice by the lanes that moved it, which is evidence for option 1 and against the filing's option-3 recommendation. THE FORK IS STILL OPEN AND STILL THE OWNER'S: nobody has bumped the mark or resolved it, and the question -- what a shared gate should do when its watched number grows from other lanes' normal work -- is unchanged by the instance being clean."
---

# Decide: what should a shared gate do when the number it watches grows as a side effect of other lanes' normal work?

- **Type:** decision (Track U) — filed by the coordinator, 2026-08-30, on pxx-a5's
  escalation. **pxx-a5 identified the fork and refused to resolve it unilaterally**,
  which is the correct handling and the reason this ticket exists.

## The concrete instance

`tools/exit_observable_devtest.py` section 3 holds a high-water mark on the number
of cross-target rows that compare **stdout only**, without the exit code. The mark
was armed today at 02:53 by `f444a4a33` — *"sweep(T): the exit-code family is clean;
the exposure is 531 stdout-only rows."*

Counted per Makefile commit rather than reasoned about (pxx-a5):

| commit | lane | count | delta |
| --- | --- | ---: | ---: |
| `f444a4a33` (armed) | T | 531 | — |
| `8b85e4881` | P | 544 | +13 |
| `df690b519` | A+S | 548 | +4 |
| `df8731b1f` | O | 550 | +2 |
| `6ef921b4e` | O | 551 | +1 |

**Four commits, three lanes, six hours.** No lane did anything wrong; adding a
cross-target row that checks stdout is the ordinary way to add a test here.

## The fork

1. **Hold the red.** Honest, and it is what a ratchet is for. But the gate is now
   red for reasons that belong to three other lanes, and a standing red that nobody
   owns is the state a red is supposed to prevent.
2. **Bump the mark when it is reached.** pxx-a5's objection, and it is correct:
   *"a high-water mark raised whenever it is reached measures nothing, and it is the
   same move as widening a tolerance until the guard stops complaining."*
3. **Report the drift and its attribution without failing.** The check's own
   docstring says its job is that the number *"cannot drift upward unnoticed"* — and
   **noticing does not require a gate failure.** A per-commit attribution table like
   the one above is strictly more informative than a red, and it is what a reader
   actually needs.

## Why this is Track U and not a T fix

The narrow question is a `tools/**` change and T could make it in a minute. The
question underneath is **what a shared gate is for** when the thing it watches is a
population that grows from other lanes' normal work rather than from a defect. That
generalises past this file to every ratchet the fleet grows, so it should be decided
once, by the owner, rather than settled per-guard by whichever agent is holding it.

**Recommendation: option 3**, with the attribution table emitted on every run. It
preserves the property the check was built for, removes a red that no lane can be
asked to fix, and does not manufacture the false comfort of option 2. If the owner
wants the pressure of a red, option 1 is defensible — but then the standing 531 needs
an owner and a plan, not just the 20 that landed after the line was drawn.

## What is already filed separately, and is NOT this decision

`bug-a-twenty-new-cross-target-rows-compare-stdout-without-the-exit-code` [A p40] —
scoped deliberately to the **20 rows that landed after the mark was armed**, not the
standing 531, because those authors are known and the diffs are small. The rows are
Makefile lines, so **T files and does not fix**. That ticket is ordinary work and
proceeds whatever is decided here.

## Do not resolve this by bumping the mark

Recorded explicitly because it is the path of least resistance and it is available to
any agent that reaches the red. See face 179 in
[[feature-a-a-refusal-is-a-claim-with-a-date-on-it]] — a threshold quietly re-priced
is indistinguishable from a threshold that was never load-bearing.

---

## MEASURED AGAIN 2026-08-30 (evening) by frankT — the table above stops five hours early, and the missing hours point the decision the other way

Re-derived per Makefile commit, same method, carried past where the ticket's
table ends:

| commit | when | lane | stdout-only | delta | what |
| --- | --- | --- | ---: | ---: | --- |
| `f444a4a33` | 02:53 | T | 531 | — | the mark is armed |
| ... | | P/A+S/O | 551 | +20 | where the table above stops |
| `a7bad7937` | 07:02 | S | **559** | +8 | it kept climbing after the ticket was filed |
| `d9d166f7e` | 07:58 | **A** | **531** | **−28** | *"28 cross-target rows now assert the exit code"* |
| `4afd5cd0f` | 08:11 | S | **533** | +2 | two unwind-cleanup programs wired into test-xtensa |

**A lane paid the whole thing down, to the mark, exactly, within six hours of
the mark being armed** — and `bug-a-twenty-new-cross-target-rows-compare-stdout-without-the-exit-code`
is in `done/`. The peak was 559, not 551.

**This weakens option 1's main objection rather than option 1.** The case
against holding the red was *"the gate is red for reasons that belong to three
other lanes, and a standing red that nobody owns is the state a red is supposed
to prevent."* Measured: it was owned, and paid, and the ratchet is what applied
the pressure. Option 3 would have replaced a red that worked with a table
nobody had to act on.

**The residual is 2 rows from ONE commit with a named author**, added 13
minutes after the paydown:

```
xtensa/test_managed_exception_cleanup
xtensa/test_interface_arc_exc
```

Both are **exception/unwind** subjects, which is the shape where the exit code
is most likely to be the real observable and stdout can match while the process
dies differently. So the cheap fix is also the valuable one, and it is two
Makefile lines.

**Still not resolving this, and still not bumping the mark** — the ticket is
right that bumping is the path of least resistance and that this is the owner's
call. What has changed is the evidence, and a decision made on the 551 table
would be made on a number that stopped being true at 07:58. Recorded rather
than acted on: **T files and does not fix Makefile rows** (this ticket says so
itself), and the two rows belong to Track S/A.

One thing I could not check from here and did not guess: whether adding
`; echo "exit=$$?"` to those two rows passes. Both sides run the same program,
so it should be free — but the xtensa side needs qemu, and asserting that a
change is safe without running it is how the row this whole family came from
was written in the first place.

## CLOSED 2026-08-30 21:58 by A+S — and the answer to the qemu question above is "it passes"

`7d1f9aeb4` — *"test(A+S): the last two stdout-only cross rows assert the exit
code too"*. Both rows now carry `; echo "exit=$$?"` on **both** sides
(`Makefile:14487` and `:14490`), the stdout-only count is back at **531**, and
`tools/exit_observable_devtest.py` reports **9 guards, 0 FAIL**.

That closes the instance and it does **not** close this ticket. What it does is
add a second data point to the evidence, in the same direction as the first:
**the ratchet has now been paid down twice, both times by the lanes that moved
the number, within hours of it going red.** The filing's case for option 3 was
that a standing red belonging to three other lanes is a red nobody owns.
Measured twice, it was owned twice. A drift table would have been read by
nobody and paid by nobody.

The decision is still the owner's, because the question was never about these
rows — it is about every ratchet the fleet grows, and a guard that happened to
get paid is not a proof that the next one will be.
