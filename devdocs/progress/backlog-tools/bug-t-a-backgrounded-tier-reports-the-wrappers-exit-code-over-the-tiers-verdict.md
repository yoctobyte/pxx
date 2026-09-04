---
track: T
prio: 55
type: bug
status: backlog
found: 2026-09-03
found-by: frankuser
owner: ""
blocked-by: []
summary: "A backgrounded `gate.sh`/`testmgr` run reports `exit code 0` in its completion notification while its own log says `testmgr: RED` / `gate: RED (exit 1)`. SEVEN independent sightings across at least three sessions since 2026-09-02. The notification is not wrong about anything — it reports the WRAPPER's exit status, and the wrapper succeeded at running the tier. It is read as the tier's verdict, because that is the only number a completion notification usually carries. CLAUDE.md already tells every agent to grep the log instead, which is a documented workaround for a live defect, not a fix."
---

# A backgrounded tier reports the wrapper's exit code over the tier's verdict

## The shape

This is the house failure mode exactly: **an instrument that lies by being
correct about something else.** The notification does not error and does not
guess — `0` is the true exit status of the process that was backgrounded. The
tier's verdict lives in the log, and nothing propagates it outward.

The reader has no way to tell the two apart from the notification alone, because
a completion notification that carries an exit code is *normally* carrying the
verdict. So the failure is silent in both directions: a RED reads as green, and
nobody who reads it green goes looking.

## Why prio 55 rather than a note in a handbook

CLAUDE.md's per-fix loop already says: *"Background it and grep the log for the
verdict — a backgrounded gate's notification reports the WRAPPER, and said
`exit code 0` over `gate: RED (exit 1)` three times in one day."* That line has
been in place since 2026-09-01 and the count has since reached **seven**. A rule
that every agent must remember, forever, to compensate for a tool that reports
the wrong number is the workaround, not the repair. **A guard that requires
discipline to read correctly has already failed once per reader.**

## What a fix has to establish

The wrapper must exit nonzero when the tier it ran was RED — or the notification
must carry the tier's verdict rather than a process status. Either is fine; what
is not fine is a green number sitting where a verdict is expected.

**Positive control, and it must be drawn from the right population:** a
backgrounded run of a tier that is KNOWN RED must produce a non-green
notification. A run that merely fails to start does not exercise this — the
wrapper fails there too, so that row passes today and certifies nothing.

## Sightings

Seven, counted by frankb-78 (which found the last of them while landing
`2aedcd004`) and by the sessions before it; the arc is recorded in
`devdocs/progress/HANDOVER-shortstring-night.md`, which logs several directly.
