---
summary: "The health VERDICT landed (trackt health, e6ee21fcc) but nothing on xeon delivers it — no timer, no toast. The watcher can go wedged with nobody told."
type: task
track: T
prio: 50
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
