---
summary: "The health VERDICT landed (trackt health, e6ee21fcc) but nothing on xeon delivers it — no timer, no toast. The watcher can go wedged with nobody told."
type: task
track: T
prio: 50
status: done
---

# The truth-teller shipped; the megaphone was never wired

- **Type:** task (Track T — host configuration, deliberately NOT committed)
- **Opened:** 2026-08-02, splitting the unfinished half out of
  [[feature-t-watcher-health-verdict-and-host-local-alerting]] (resolved
  `e6ee21fcc`).

## What landed

`trackt health` / `trackt health --json` — one command combining liveness,
wedged-detection (phase=testing with `live.json` frozen), publish health and
coverage into a verdict plus exit code. Portable, in the repo, works headless.
`gate.sh check` points at it (`a483dcf95`).

```
$ ./trackt health --json
{"verdict": "OK", "exit": 0, "reasons": ["daemon 3442406, phase=testing, publishing clean"],
 "host": "xeon", "clone": "/home/neo/trackt-watch"}
```

## What did not

The delivery half. Everything is still **pull**: someone must think to run the
command. On xeon there is no timer and no notifier —
`systemctl --user list-timers` shows `xeon-fanwatch`, `xeon-pet-selfcheck` and
`xeon-away-monitor`, but nothing for the watcher. So the failure this ticket
family exists to catch — daemon alive but wedged — still reaches a human only
by luck.

What has been standing in for it is an **agent-session observer script**
(`watch-trackt.sh` in a session scratchpad, polling every 300s). That is not a
solution: it dies with the session, it lives outside the repo *and* outside the
host's own service config, and on 2026-08-02 one was found still looping hours
after its session had ended, emitting to nobody.

## Asked for

A systemd **user** timer on xeon, in `~/.config/systemd/user/` alongside the
existing `xeon-*` units, NOT in the repo:

- `trackt-health.service` — `ExecStart=.../trackt health --json`, `Type=oneshot`
- `trackt-health.timer` — every 5-10 min
- on non-zero exit, deliver: `notify-send` while a graphical session exists,
  with a fallback that survives a headless boot (append to a log the
  pet-selfcheck already surfaces, or `USER_ATTENTION.md` per
  `~/USER_ATTENTION_PROTOCOL.md`).

Per `two-box-protocol.md` an alert is a **hint**, never state: it says "look at
git", it does not carry a verdict anyone acts on directly.

**Poll, not push** — settled by
[[decide-t-notification-transport-poll-not-webhooks]] (2026-08-02): the timer
polls `trackt health` locally and delivers on non-zero. No webhook, no callback
URL, nothing requiring inbound reachability. A backoff when the verdict has been
OK for a long stretch is allowed here (this loop is a plain timer, unlike the
daemon's work-gated one) but is not required — a 5-10 min timer running a
sub-second command costs nothing worth optimising.

## Why it stays out of the repo

A toast needs a graphical session, a D-Bus address and a desktop that shows
toasts. The repo is shared with boxes that have none (a Pi oracle, a container,
borg). Enrolling a new watcher gets the truth-teller for free and wires
whatever megaphone that platform has — a desktop toast, mail, a log the
selfcheck surfaces, an ssh poke at a peer. All *outbound* from the box that
already knows the answer; nothing that has to be called back into.

## Gate

`-STOP` the daemon mid-run and confirm a notification arrives within two timer
intervals, then `-CONT` and confirm it clears. Verify the unit is `enabled` so
it survives a reboot — the failure mode of host-local config is that it is set
up once, interactively, and never comes back.

## DONE 2026-08-13 — the megaphone is wired, and the Gate above is wrong

### First, the name

The slug says "xeon"; this box was renamed **plexus** on 2026-08-04. Same
machine — `hosts.json` carries `renamed_from: xeon` and the *identical*
fingerprint `fc0640930141` either side of the rename. `trackt health` already
reports `"host": "plexus"` correctly, so only the prose (and this slug) were
stale. Nothing installed below is host-name-dependent.

### Installed on plexus (host config, NOT in the repo — inlined here so it is recoverable if the box is rebuilt)

| path | what |
|---|---|
| `~/.local/bin/trackt-health-alert.sh` | the megaphone |
| `~/.config/systemd/user/trackt-health.service` | `Type=oneshot`, `Nice=10`, `IOSchedulingClass=idle` |
| `~/.config/systemd/user/trackt-health.timer` | `OnBootSec=3min`, `OnUnitActiveSec=5min`, `Persistent=true` |
| `~/.local/state/trackt-health/` | `last_verdict`, `streak`, `alerts.log`, `attention_owned` |

`enabled` and running; verified scheduling live (`NEXT … LEFT 4min 52s`).
Deliberately named `trackt-health`, not `plexus-trackt-health`: it is about the
watcher, not the host, and that also sidesteps the stale `xeon-*` prefix the
other three user units still carry.

### EDGE-triggered, because the protocol says so

`~/USER_ATTENTION_PROTOCOL.md`'s attention budget: *"do not interrupt more than
once for the same issue unless the situation changed materially."* A 5-minute
timer that toasts every tick is exactly how a human learns to ignore us. So the
script notifies and logs on the **transition** and stays silent while the state
persists. Measured: four consecutive DOWN checks produce **one** line in
`alerts.log` and **one** toast.

Three delivery tiers, escalating:

1. **always** — a transition line in `~/.local/state/trackt-health/alerts.log`
   (headless-safe; no display, no D-Bus, no network needed).
2. **on transition, if a graphical session exists** — one `notify-send`.
3. **after 3 consecutive bad checks (~15 min)** — a `REQUEST` in
   `~/USER_ATTENTION.md`, which the pet dashboard already surfaces.

### The single-slot problem, and why tier 3 is guarded

`~/USER_ATTENTION.md` holds **one** item and a human or another agent may be
holding it — it currently holds a live `REQUEST` about a BIOS fan message. An
automated timer that writes there unconditionally destroys whatever it finds.
So tier 3 writes **only over an `INFO` status**, and when the slot is taken it
records `ESCALATION SUPPRESSED: USER_ATTENTION.md holds a live REQUEST` in its
own log instead of fighting for it. On recovery it does the protocol's own
Cleanup step: appends an outcome to `~/USER_ATTENTION_LOG.md` and restores the
prior contents. Verified both ways, including that a human's `REQUEST` survives
four DOWN checks untouched.

An unparseable verdict (trackt missing, clone gone, python broken) is treated as
a **fault**, not silently as OK.

### The Gate as written does not work — live.json is the CHILD's

> *"`-STOP` the daemon mid-run and confirm a notification arrives within two
> timer intervals"*

It will not. The WEDGED check is "phase is a gate phase AND `live.json` has not
moved in >180 s" — and **`live.json` is written by the `testmgr` child process,
not by the daemon**. Confirmed on the running watcher: daemon `2213545`, child
`2570778` (`testmgr.py --tier full`). SIGSTOP the daemon and the child keeps
testing and keeps `live.json` fresh, so `health_check` sees a live pid, a gate
phase and a moving `live.json` — verdict OK. Nothing fires until the child
exits, minutes later.

This is not just a bad test recipe; it is a small gap in the health check
itself. A daemon frozen while its child works is invisible for as long as the
child has work left. It *is* caught eventually (the child exits, `live.json`
goes stale, WEDGED fires 180 s later), so the detector is late rather than
absent — but "confirm within two timer intervals" is not a promise it can keep.
**Not filed as a separate bug**: the delayed detection is arguably correct
behaviour (a frozen daemon with a working child is still producing results), and
deciding whether the daemon needs its own liveness beat is a design call. Worth
one, if someone disagrees.

### What was verified instead

Every path was exercised against a **fake clone** via the env overrides the
script now carries (`TRACKT_HEALTH_BIN`, `TRACKT_HEALTH_STATE`,
`TRACKT_HEALTH_ATTENTION`, `TRACKT_HEALTH_ATTENTION_LOG`) — which also means the
gate is re-runnable at any time instead of needing a broken daemon on demand:

- OK -> DOWN transition: one log line, one toast, streak counting
- DOWN x4: still one log line (edge-triggering holds)
- escalation at streak 3 writes `USER_ATTENTION.md` when the slot is `INFO`
- escalation suppressed, and the human's text intact, when it is not
- DOWN -> OK: outcome appended to `USER_ATTENTION_LOG.md`, prior contents
  restored, `attention_owned` cleared
- unparseable output -> `UNPARSEABLE`, delivered rather than swallowed

Plus, against the **real** `health_check` (real code, real verdict string) on a
clone with no daemon:

```
{"verdict": "DOWN", "exit": 2, "reasons": ["no watcher daemon is running"], "host": "plexus", ...}
  -> 2026-08-13 18:19:15 CEST  OK -> DOWN   no watcher daemon is running
```

And the failure mode that actually breaks tasks like this — a notifier that
works in a shell and silently does nothing from a unit:

```
$ systemd-run --user --wait notify-send ...   ->  rc=0, toast delivered
```

The user manager carries `DISPLAY=:0`, `WAYLAND_DISPLAY=wayland-0` and
`DBUS_SESSION_BUS_ADDRESS`, so the timer inherits what it needs.

### What was NOT verified, and why

A true `systemctl --user stop/start trackt-watcher.service` end-to-end. The
watcher was 43% into a full tier when this landed, and discarding ~10 minutes of
matrix coverage would have bought nothing the daemonless-clone test above did
not already prove — same `health_check`, same verdict, same delivery. Worth
doing opportunistically the next time the watcher is idle between runs.

## Log
- 2026-08-13 — resolved, commit PENDING-COMMIT.
