---
track: T
prio: 30
type: audit
status: open
found: 2026-08-30
found-by: claude-T
---

# Five verdicts in one week reported an outcome the mechanism had not decided

Not five bugs. One shape, found five times in seven days, in three tracks'
files. Filing the sweep instead of a sixth individual fix.

## The shape

**A verdict has fewer slots than the subject has outcomes, so the missing case
takes the shape of whichever neighbour the control flow happens to reach.**

It is not a bias toward alarm or toward comfort — it is an *absence with no
slot*. The same missing distinction produced opposite errors depending on which
loop it fell out of:

| instance | outcomes in reality | slots | the missing case became |
| --- | --- | --- | --- |
| `pasmith_run.recheck`, multi-unit | reproduces / fixed / **could not regenerate** | 2 | "still reproduces" — manufactures work |
| `pasmith_run.recheck`, zero examples | same | 2 | "FIXED (0 seeds agree)" — manufactures a green |
| `pasmith_run.localize`, sentinel result | a checkpoint / **no location exists** | 1 | a confident wrong checkpoint |
| `pasmith_run.ledger_status` | what throttles / what is open | 1 | reported the set that did *not* govern |
| `recheck`'s population | throttles? / re-measure? | 1 | `dodged` never re-measured at all |

Two more from the same week are the prose variant — an assertion with nothing
re-deriving it, rather than a missing slot — and they belong in the same sweep
because the repair is the same kind of thing:

- `tools/gui_shot.sh` `BLANK_MAX=4000`, on the note *"a blank frame is ~1-3 KB"*.
  True when written; by 2026-08-30 an empty display was 4013 B and a real xterm
  window 4068 B. Fifty-five bytes apart — the proxy was **dead, not
  mis-calibrated**, which is a different ticket with a different fix, and only
  measuring *both* sides showed which.
- `compiler/defs.inc:1149` — a comment describing the slot, not the variant
  (filed as `bug-a-defs-inc-vt-promo-comment-describes-the-slot-not-the-variant`).

## Why it survives review

Every one of these reads as routine at the call site. `reproduces = True` under
a comment saying *"cannot judge: keep it open, loudly"* looks like the careful
choice — and the code was not loud, it printed the same string as a genuine
reproduction. **A report is a claim, and nobody re-derives a claim that reads as
routine.** The two halves drift because nothing imports one into the other.

The latch is what gives it teeth: a false "still reproduces" is not one wrong
verdict, it is a wrong verdict that **cannot ever become right**, because the arm
that would flip it is the arm that is broken. It gates work, it gates itself, and
nothing in it decays.

## The sweep

Track T tooling only — `testmgr.py`, `twatch.py`, `pasmith_run.py`, `fuzz.sh`,
`gui_shot.sh`. For each function that returns or prints a verdict:

1. **Enumerate the subject's real outcomes**, including "I could not look".
   Compare with the slots the return type actually has. A bool has two.
2. **Where a set answers two questions**, check both answers are wanted.
   `ledger_open` was right about throttling and wrong about re-measuring.
3. **Where a report names a location, a cause, or a number**, check the
   deciding half computed it — not a neighbouring value that is usually equal.
4. **Where prose asserts a measurement**, re-derive it, and measure *both*
   sides of any comparison. One side alone cannot distinguish a mis-calibrated
   proxy from a dead one.

Bias every repair toward "I could not measure": that failure mode is
recoverable, and a clean verdict from no data is not.

## Not a rewrite

Each individual repair has been ~20 lines plus guards. The value is doing them
in one pass with the shape named, so the sixth instance is recognised rather
than rediscovered. Prio 30: nothing here is on fire, and every instance found so
far was found *while doing something else*.

## Related

[[devdocs/dev/the-empty-tree-audit]] is the detection technique for the prose
variant (a partition whose empty cell is the finding). The repaired instances
are `10c8...`-era Track T commits from 2026-08-29/30.

Gate: `tools/*_devtest.py` green for whatever is touched; pure guards preferred,
each with a negative control that goes red for the *right* reason.
