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

## Three more sightings, 2026-09-04 (frankS) — and one that is NOT this bug

Seven becomes ten. All three backgrounded `tools/gate.sh quick`, all three
`exit code 0` in the completion notification:

- two where the log agreed (`gate: GREEN (exit 0)`) — harmless, and the reason
  the defect is easy to live with;
- one where it did **not**: log said `gate: RED (exit 1)` on
  `this push wires the tests it adds`, notification said `exit code 0`.

The RED one is worth recording because the failure it was reporting was real and
would otherwise have been pushed: a Makefile row had never landed, because the
tool call carrying the patch also carried a `make test-core` that the
no-full-suite hook refused, killing the whole call. Believing the notification
would have banked a test file nothing runs.

**A fourth run the same evening was killed by the OOM reaper mid-tier** and
reported `status: killed`. That one is NOT this bug and should not be counted
toward it — the log simply had no verdict line at all, which is the honest
outcome and is distinguishable by `grep -c 'gate: \(GREEN\|RED\)'` returning 0.
Worth stating here only because "no verdict" and "wrong verdict" arrive through
the same channel and a fix that makes the notification carry the tier's verdict
needs an answer for the killed case too.

Running the gate in the FOREGROUND sidesteps all of it and costs the same ~90s.

## A SECOND MECHANISM FOR THE SAME SYMPTOM, and it defeats the documented workaround (frankB, 2026-09-04/05)

Four sightings tonight, all the same shape and **none of them the wrapper
reporting a finished tier's exit code.** The notification arrived while the gate
was still running, roughly 40 seconds in, at the `-O3 backend parity` step —
minutes before the fixedpoint and testmgr had even started.

The cause is one level out. The command backgrounded was

```
nohup tools/gate.sh quick > <log> 2>&1 &
echo "started pid $!"
```

so the process the harness tracked was the **launching shell**, which exits
immediately and truthfully with 0. `gate.sh` outlives it.

**Why this one matters more than the original:** the documented workaround —
*"background it and grep the log for the verdict"* — does not save you here. The
log at notification time is a PREFIX. Every line in it says PASS, there is no
`gate:` verdict line yet, and a `tail` of it looks exactly like a run that
passed everything so far. Grepping for `RED` finds nothing, correctly, about a
gate that has not reached the step that could produce one. So the reader can
follow CLAUDE.md exactly and still bank on an unfinished gate.

**Both mechanisms produce the identical observation** — "completion
notification, exit 0, verdict says otherwise or is missing" — so a fix aimed at
propagating the tier's verdict into the notification would leave this one live,
and a session that hit this one would report it as the known bug.

**The discriminator is whether the gate PROCESS is still alive**, not anything
in the log:

```
$ pgrep -af 'tools/gate.sh quick'
401322 bash tools/gate.sh quick        # still running, notification already delivered
```

**What worked, if a workaround is wanted before the fix:** capture the gate's
own pid and block on THAT, so the tracked process is the gate rather than its
launcher.

```
nohup tools/gate.sh quick > <log> 2>&1 & echo $! > <pidfile>
# then, as the backgrounded command:
P=$(cat <pidfile>); while ps -p $P >/dev/null 2>&1; do sleep 10; done
grep -E '^gate:|canary' <log>
```

A `pgrep -f 'gate.sh quick'` loop is NOT a substitute and cost a wasted wait
here: another session was running its own gate on the same box, so the pattern
matched a process that was not mine and the loop never returned. The pid is the
only identifier that discriminates.

Routed here rather than filed separately because the symptom, the reader's
conclusion and the damage are identical; but it is a **second cause**, and
closing the first will not close it.

