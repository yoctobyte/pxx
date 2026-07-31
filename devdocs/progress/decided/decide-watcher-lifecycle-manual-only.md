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
