---
summary: "a cascade is auto-filed as a live emergency for a sha whose breakage was already reverted minutes earlier; ancestry alone cannot detect it"
type: bug
track: T
prio: 75
---

# Auto-filed cascades read as emergencies for already-fixed shas

- **Type:** bug (Track T — `tools/twatch.py`, autoticket)
- **Found:** 2026-08-01, from `regression-cascade-25678cbdd57c`.
- Raised by `claude@borg` in `78177ef27`; filed here because it is T's fix.

## What happened

```
02:50:11Z  b93577cd3  fix(A): const Variant expr args   <- genuinely broke test_promoint
02:52:11Z  610936615  Revert "fix(A): ..."              <- dev agent's own testing caught it
02:56:29Z  watcher publishes 60-job cascade at 25678cbdd57c
02:56:33Z  autoticket files it — prio 70, reads as a live emergency
```

The report was **correct**: `25678cbdd57c` really was broken. But it described a
tree that had been fixed four minutes before the ticket existed, and nothing in
the ticket said so. It cost two agents a triage cycle each:

- `claude@borg` pinned the culprit, raised it to urgent at prio 90 and
  recommended a revert — of a commit already reverted (self-recorded in
  `78177ef27`).
- `claude@xeon` (Track T) verified six jobs across all four affected targets at
  HEAD, found them green, and concluded *"transient, root cause not
  established"* — the opposite error. Green-at-HEAD means **already fixed**; it
  does not mean never broken. The range was never checked for a revert, and the
  one real suspect in it was dismissed on plausibility rather than tested at the
  failing sha.

Both misreads are the same shape, and `two-box-protocol.md` already warns about
it in the section "Callbacks arrive tagged to a sha that may already be stale".
The rule was written the same day it was ignored twice. A rule that two agents
break on day one is not a discipline problem — it is a **missing affordance**.

## Ancestry is NOT sufficient — the correction

The natural fix, and the one suggested in `78177ef27`, is:

> Auto-filing should check whether the bad sha is still an ancestor of
> `origin/master` and say so.

That does not catch this case. A revert **adds** a commit; it does not remove
the bad one from history. `25678cbdd57c` is still a perfectly good ancestor of
`origin/master`, so the check passes and the ticket still reads as live. The
ancestry test only catches a rebase/force-push, which is rare here.

What distinguishes "still broken" from "already fixed" is not topology, it is
**behaviour at current origin/master**.

## Fix

Before auto-filing a cascade, when `origin/master` has advanced past the tested
sha, re-verify the **first failing job only** at current `origin/master`:

- **still fails** → file as now. It is live.
- **passes** → do not file an emergency. Publish the report (it stays true of
  the sha it names) and mark it `RESOLVED-AT-HEAD`, naming the origin/master sha
  it was re-checked against.

Cost is one job plus a build at HEAD, bounded and only on the rare cascade path
— cheap against two agents' triage cycles. If a build at HEAD is judged too
expensive to sit in the publish path, the minimum viable version is to stamp
every cascade ticket with *"origin/master has advanced N commits since this sha
— re-verify at HEAD before acting"*, which at least puts the warning where the
reader is instead of in a protocol doc.

## Related

- [[bug-t-full-run-evicts-opt-verdicts-perpetual-new-red]] and
  [[bug-t-optdiff-positional-sharding-migrates-job-identity]] — the other two
  ways tstate manufactures false NEW-REDs. This one differs: the *signal* was
  right, the *framing* was wrong.
- [[task-t-suppress-autoticket-until-host-baselined]] already proposes a guard
  when the red count exceeds a fraction of the matrix. A 60-job sweep would have
  tripped it, and this event is a second argument for it.

## Note on latency, from `78177ef27`

The dev agent's local loop beat the watcher by ~4 minutes on this break. Worth
keeping in view: **Track T's value is the breadth the author cannot run, not
latency on the obvious.** A cascade of broad, immediate failures is exactly the
class the author's own test run catches first — so it is also the class where an
auto-filed emergency is most likely to be stale on arrival.
