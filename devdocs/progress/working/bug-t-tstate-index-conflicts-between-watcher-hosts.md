---
summary: "TSTATE.md is regenerated wholesale by every host, so two live watchers rebase-conflict on it and silently drop verdicts"
type: bug
track: T
prio: 70
---

# Two watcher hosts fight over `TSTATE.md` and drop each other's verdicts

- **Type:** bug (Track T — `tools/twatch.py`, publish path)
- **Found:** 2026-07-31, running xeon and borg concurrently during the cutover.

## Symptom

```
publish: ⚠ BLOCKED — 1 consecutive drop over 36s (last: rebase conflict onto origin)
         stale verdicts are being discarded each cycle
twatch: publish conflicted with origin (rebase conflict onto origin)
        — dropped this cycle's tstate commit; will republish against fresh origin next cycle
```

xeon completed a native gate at `f3d420def527`, produced a correct RED verdict,
and **threw it away**. Its `TSTATE.md` row stayed pinned at `110774a14648` —
three cycles stale — while the daemon looked healthy in every other respect.

## Cause

`devdocs/progress/tstate/TSTATE.md` is *"regenerated index over all host state
files"* (twatch.py:23, written at :615). Every host rewrites **the whole table,
including the other hosts' rows**, on every publish. So whenever two watchers
publish inside the same window, both commits touch the same lines of the same
generated file and the rebase in `publish()` conflicts. On conflict
`_drop_to_origin()` discards the cycle's commit — by design, so the daemon can
never wedge — and the verdict is simply lost.

The per-host **data** files are fine: `<host>.json` and `runs-<host>.ndjson` are
single-writer and merge cleanly. It is only the shared generated **index** that
collides. `BOARD.md` has exactly this shape and was already solved:

```
devdocs/progress/BOARD.md merge=ours
```

`TSTATE.md` never got the same treatment.

## Why it is worse than "redundant"

The deploy note says several watcher hosts in parallel are fine because "reports
are host-tagged, pushes rebase-retry". Host-tagging is true; rebase-retry does
not save this case, because the retry re-hits the same conflict. Adding a second
watcher does not just duplicate work — it **degrades both hosts' publish rate**,
and it does so quietly, because a dropped verdict leaves no red mark anywhere
except the `publish:` line in `trackt status`.

## Fix

1. **Regenerate `TSTATE.md` after the rebase, immediately before the push** —
   the correct fix. The index is a pure function of the `<host>.json` files, so
   it should be rebuilt from whatever origin state won the race rather than
   carried through the rebase as content. Then it can never conflict.
2. Cheap interim, mirroring BOARD.md: add
   `devdocs/progress/tstate/TSTATE.md merge=ours` to `.gitattributes` and run
   the documented one-time `git config merge.ours.driver true` per watcher
   clone. Self-heals on the next regeneration.
3. `trackt setup` should run that `git config` itself — it is required for
   `BOARD.md` too, it is not committable, and a fresh watcher clone silently
   lacks it. (xeon's clone did; set by hand on 2026-07-31.)

## Note

Not a blocker for the borg→xeon cutover: with a single live watcher there is no
second writer and the conflict cannot occur. It *is* a blocker for ever running
two watchers, which the deploy documentation currently advertises as supported.
