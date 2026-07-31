---
prio: 50
---

# DECIDE: the watcher daemon is started and stopped BY HAND — no supervision

- **Type:** decide (user call — an operator preference, not a technical fork)
- **Track:** T (watcher lifecycle)
- **Status:** done
- **Owner:** — (user)
- **Decided:** 2026-07-31, verbally, at the xeon box

## DECIDED — strict manual control. Do not install supervision.

Asked whether the twatch daemon should be made durable on xeon, the user's
answer was **"no. strict manual control."**

That rules out, on this box and until the user says otherwise:

- a systemd user unit (`Restart=always`, `WantedBy=default.target`)
- `loginctl enable-linger neo`
- cron `@reboot`, or any other auto-start hook
- any watchdog process that restarts the daemon

**Do not propose these again as a fix for an observed outage.** If Track T is
found down, the answer is to tell the user, not to make it restart itself.

## What this means operationally (the accepted trade-offs)

Recorded so nobody "discovers" these later and reads them as bugs:

| | consequence |
|---|---|
| reboot | coverage ends silently; `./trackt up` by hand to restore it |
| daemon crash | nothing restarts it. The loop catches `RuntimeError`/`SubprocessError`/`OSError` per cycle, so gate failures and push rejections are survived — but an unexpected exception type escapes and ends the process |
| last logout | `Linger=no`, so the systemd **user manager** stops. twatch itself survives (`KillUserProcesses=false`), but testmgr's `systemd-run --user --scope` degrades to an **unscoped** run — the `MemoryMax` backstop against a box freeze is then absent |
| logging | `~/trackt-watch.log` is unrotated and grows (2.2 MB in the first ~2 h) |

The state as of this decision: PID detached (PPID 1, own session), so it is
immune to the terminal and to the tmux session going away. It is only exposed
to reboot, crash, and full logout.

## The stakes changed the same day — the decision has NOT been revisited

This was decided when the watcher was *coverage*: if it stopped, the fleet lost
breadth and someone eventually noticed. Hours later the operating model made
xeon's `fast_tier` **the project gate** (`two-box-protocol.md`, "Do not RUN
native on the dev box"): dev boxes now push after a ~15 s `--tier quick` and
rely on xeon's native run arriving ~3 min later.

`quick` does **not** carry the self-host fixedpoint (`SELFHOST_GATE_TIERS =
native/limited/full`). So a hand-started, unsupervised watcher is now the only
thing running the gate that the stable binary rests on.

The failure window is bounded but real, and it is the *false UP* direction:

- `twatch --status` counts T as UP iff every commit older than the grace window
  (default **45 min**) was tested by some host. A watcher that died a minute ago
  therefore still reads **UP**.
- During that window a dev box pushes on quick, believing native will follow.
  It will not, and nothing says so.
- The opposite error (false DOWN, the known `--status` bug) is merely wasteful:
  dev boxes run their own full gate unnecessarily. That direction is safe.

So the exposure is roughly *one grace window of pushes landing with no
fixedpoint check, with no signal*. Not an argument against the decision — the
user owns this call and it stands. Recorded because:

1. it is new information relative to when the call was made, and
2. it moves [[bug-t-twatch-status-false-down]] / watcher-liveness detection from
   "annoying" to "the compensating control" — with no supervision, *detection*
   is the entire safety net, and it is the piece that does not work yet.

Practical mitigation available today, costing nothing and needing no
automation: **check `trackt status` when you sit down at either box.** One line,
and it closes the window that matters.

## For the peer box

`claude@borg`: this is a standing user preference for the fleet's watcher host,
not an xeon quirk. If the watcher is ever re-enabled on borg, the same rule
applies — start it by hand.

## Still open, and NOT covered by this decision

Nothing here fixes the *detection* gap: liveness is pull-only via
`tools/twatch.py --status`, which is also the check with the known false-DOWN
bug (reports DOWN whenever tstate is stale, including while a run is provably
in progress). Manual lifecycle makes that gap matter more, not less — the
sooner an agent can trust `--status`, the sooner a hand-stopped watcher gets
noticed. That work is unaffected by this decision and should still happen.
