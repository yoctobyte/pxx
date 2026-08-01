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

---

## REVERSED IN PART — 2026-08-01, user, at the xeon box

> "fix 2. survive reboots (we can assume user auto login btw..)"

Reboot survival is now **installed**, superseding the "no systemd unit, no
linger, no cron" line above. What did *not* change: stopping the watcher by hand
still means stopped.

### What was installed

`~/.config/systemd/user/trackt-watcher.service`, enabled `WantedBy=default.target`,
plus `loginctl enable-linger neo`.

**`Restart=on-failure`, deliberately not `always`.** A crash or an OOM kill is
restarted after 30s; a clean `trackt stop` sends SIGTERM, twatch's handler exits
0, and systemd leaves it stopped. So the original intent — *the operator decides
when the watcher runs* — survives, while the two failure modes that were pure
downside (reboot, crash) no longer end coverage silently.

**Linger does double duty.** It starts the service at boot rather than only at
login, and it keeps the systemd **user manager** alive across a full desktop
logout. That closes the caveat recorded earlier: testmgr re-execs into
`systemd-run --user --scope` for its memory cgroup, and without a user manager
that call fails and the run degrades to *unscoped*, losing the backstop that
makes a box freeze structurally impossible.

The unit deliberately sets no resource limits of its own — a nested scope under
a constrained service would inherit the tighter limit and silently undo the
per-run budget testmgr computes from `MemTotal`.

Logging still appends to `~/trackt-watch.log` so `trackt log` and the session's
history keep working; journald would have fragmented it.

### What this does NOT change

The detection gap is still the real exposure and is unfixed by supervision:
`twatch --status` reads UP for up to the 45-minute grace window after the daemon
dies. Restart-on-failure narrows the window for crashes; it does nothing for a
watcher that is running but wedged.

Deploying new `twatch.py` code is now `systemctl --user restart
trackt-watcher.service` rather than `trackt stop && trackt up`. `trackt`'s own
detection is unaffected — `daemon_pid()` scans `/proc` by command line, so a
systemd-started daemon is found normally.
