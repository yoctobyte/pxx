---
summary: "Nothing detects a watcher that is running but wedged, and nothing pushes a problem at anyone. Split it: a portable health verdict in the repo, platform-specific delivery on the host."
type: feature
track: T
prio: 70
---

# Can we trust the watcher, and how does it tell anyone when we can't?

- **Type:** feature (Track T) — **Track T**
- **Opened:** 2026-08-01, user question at the xeon box.

## Two problems, and they are not the same

**1. Trust.** `twatch --status` infers health from *coverage* only: "was every
commit older than the grace window tested by someone". That cannot distinguish

| actually | reads as |
|---|---|
| daemon dead | DOWN, after up to 45 min |
| daemon running but **wedged** | DOWN, after up to 45 min |
| daemon healthy, repo simply quiet | UP |
| your checkout is stale | (was DOWN — fixed in `c665a27ed`) |

A wedged daemon is the worst case and the least visible: the process is alive,
`trackt status` says RUNNING, and the only symptom is that nothing advances.

**2. Delivery.** Everything today is **pull** — someone must run `--status`,
`--follow` or `trackt status`. Nothing pushes. The operator finds out when they
think to look, which is exactly when they are least likely to.

## The primitives already exist

The daemon already writes three files; nothing combines them:

| file | says | freshness |
|---|---|---|
| `.testmgr/watch.json` | phase, sha, tier, pid | per phase change |
| `.testmgr/live.json` | pct, done/total, eta | **per second, during a run** |
| `.testmgr/pubhealth.json` | consec_drops, last_push_ts, behind | per publish |

`live.json` is the missing wedged signal: if `watch.json.phase == "testing"` but
`live.json` has not moved in minutes, the daemon is alive and **not working**.
That is a direct observation, not a 45-minute inference.

## The split — and why it matters here

The user's own framing is the right architecture: **xeon is "just" a Track T
user**, and a desktop toast is platform-specific.

- **In the repo (portable, Track T's lane): the VERDICT.** One command that
  combines liveness, wedged-detection, publish health and coverage into a
  verdict plus an exit code and `--json`. No platform assumptions: works on a
  headless box, a Pi, a container, borg.
- **On the host (NOT committed): the DELIVERY.** A systemd user timer on xeon
  that runs the verdict and pipes a failure into `notify-send`. That depends on
  a graphical session, a D-Bus address, a desktop that shows toasts — none of
  which belong in a repo shared with boxes that have none.

Concretely: **the repo gains a truth-teller; the box gains a megaphone.** Anyone
enrolling a new watcher gets the truth-teller for free and wires whatever
megaphone their platform has — mail, ntfy, a webhook, an ssh poke to a peer.

A toast is also not *state*: per `two-box-protocol.md`, state goes through git
and only git. An alert is a hint that something in git deserves a look.

## Verdict shape

```
trackt health            # OK / DEGRADED / DOWN + reasons
trackt health --json     # machine-readable, for the notifier
```

| verdict | exit | when |
|---|---|---|
| OK | 0 | daemon alive, advancing (or legitimately idle), publishing, coverage current |
| DEGRADED | 1 | publishing dropped repeatedly, or coverage behind, but the daemon is working |
| DOWN | 2 | no daemon, or wedged: phase=testing with `live.json` frozen |

"Legitimately idle" matters: a quiet repo is not a fault, and conflating the two
is what made `--status` untrustworthy in the first place.

## Gate

Kill `-STOP` the daemon mid-run (alive, frozen, `live.json` stops moving) and
confirm `trackt health` reports DOWN/wedged within one poll — not after the
45-minute grace window, and distinguishably from "no daemon" and from "idle".

## Log
- 2026-08-02 — resolved, commit e6ee21fcc.
- 2026-08-02 — resolved for the REPO half only. `trackt health` / `--json`
  landed in `e6ee21fcc` (verdict, exit code, wedged-detection off a frozen
  `live.json`) and `gate.sh check` points at it (`a483dcf95`). The HOST half —
  the megaphone, a systemd user timer on xeon piping a non-zero verdict into a
  notifier — was never wired: `systemctl --user list-timers` shows the three
  `xeon-*` units and nothing for the watcher. Split out as
  [[task-t-xeon-host-local-health-alerting]] rather than left implicit here,
  because the ticket's own architecture says that half is deliberately NOT
  committed and so cannot be judged from the repo.
  The gate stated here (`-STOP` the daemon mid-run, confirm DOWN/wedged within
  one poll, distinguishable from idle) was NOT re-run today — the daemon was
  mid `--tier full` and stopping it to test the detector would have cost the
  matrix run. It carries over to the split ticket.

