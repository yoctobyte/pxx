---
slug: feature-t-a-user-hold-must-survive-a-bulk-re-price
track: T
prio: 55
type: feature
blocked-by: []
status: open
created: 2026-08-30
summary: "One commit (ab584382e, `apply the approved re-triage`) erased two user rulings in the same sweep -- the ESP park and the NilPy except-tuple hold -- because each was enforced only by a `prio:` number with the reason in a `#` comment, and a bulk re-price rewrites numbers and drops comments. Both instances are now closed on their merits, so this is not urgent; it is filed because the next hold will be recorded the same way unless the recording form changes."
---

# T: a user hold enforced by a number does not survive a process that rewrites numbers

## The event

`ab584382e` (2026-08-25), *"tickets: apply the approved re-triage — prio now
spans 3-88"*:

| ticket | was | became |
| --- | --- | --- |
| `feature-pal-esp-posix-fd-semantics` | `prio: 30  # ESP parked (user 2026-07-12): Pascal has prio` | `prio: 20` |
| `bug-nilpy-except-tuple-binder-is-typed-by-the-first-arm-only` | `prio: 20` (held 2026-08-14) | `prio: 55` |

**One commit, two user rulings, neither named in its message.** Nothing about
the re-triage was a decision to lift either hold. Discovered independently by
frankB and the coordinator on the same night, from opposite ends —
[[decide-is-the-2026-07-12-esp-park-still-in-force]].

## The tell worth keeping

The ESP park **survived in both `done/` tickets that carried it and was deleted
from the one live ticket**, because a re-triage re-prices open tickets and does
not touch `done/`. Enforcement was destroyed exactly where it was load-bearing
and preserved exactly where it was inert — which is why it read, six weeks
later, as a fossil that had never had a mechanism, when in fact it had one and
the mechanism was overwritten.

Generalised: **if a rule appears to survive only in places where it cannot act,
it has probably already been erased where it mattered.** That is a cheap check
and it is the one nobody ran.

## Why this is filed anyway, with both instances closed

The ESP park expired on its own terms (owner, 2026-08-30: *"ESP is not parked -
that was temporary"*) and the NilPy hold was repaired with a `NOT DISPATCHABLE`
marker. So nothing is currently broken and this is deliberately not urgent.

It is filed because the *recording form* is unchanged. The next time the owner
holds something, the natural thing to write is still a `prio:` comment, and the
next bulk re-triage will still erase it. Two instances in seven weeks is not a
coincidence; it is the rate.

## What would fix it

The two forms that survive a re-price already exist in the tree, because they
are not prices:

- `NOT DISPATCHABLE` in the ticket body (what repaired the NilPy hold);
- a `blocked-by:` edge on a `decide-` ticket (what
  `feature-dns-esp-wire-nameservers-from-lwip` used, correctly, without
  presuming the answer).

So the work is not inventing a mechanism. It is:

1. **Make the tooling refuse to silently drop one.** A re-price that changes a
   `prio:` line carrying a `#` comment should either preserve the comment or
   fail loudly. Cheapest possible version, and it alone would have prevented
   both instances.
2. **Give the ranker something to report.** `progress.sh check` (or `ready`)
   should be able to answer *"what is currently held, and by whom"* — today
   there is no way to ask, which is why a park could be invisible for six weeks
   while sitting intact in a live ticket's frontmatter.
3. **Say so in the docs.** `devdocs/progress/README.md` should state that a hold
   goes in the body or an edge, never in a `prio:` comment, and why.

Item 1 is the whole value; 2 and 3 are what stop it recurring in a different
shape.

## Gate

Track T's own tooling gate. Plus the functional check that settles item 1:
re-price a ticket whose `prio:` line carries a comment and confirm the tool
either keeps the comment or refuses. Re-running the two historic cases against
the changed tool is the honest regression test — both are in `git log`.
