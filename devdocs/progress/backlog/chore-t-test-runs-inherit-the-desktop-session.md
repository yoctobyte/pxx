---
track: T
prio: 55
type: chore
summary: "Every systemd-run --user job on plexus inherits a full desktop session — DBUS_SESSION_BUS_ADDRESS, DISPLAY=:0, WAYLAND_DISPLAY, XAUTHORITY — because systemctl --user show-environment carries them and the watcher's own /proc/<pid>/environ has them all. a11y was the symptom that hung a job for three days; anything that opportunistically talks to a display or session bus can hang the same way. Strip the environment for test runs instead of blocklisting symptoms one variable at a time."
---

# Test jobs inherit the human's desktop session

- **Type:** chore/infra — **Track T** (testmgr's job launcher).
- **Follow-up to** the 2026-08-25 repair (`fix(T): one hung job stopped costing
  the run every other verdict`), which turned the a11y bridge off in
  `job_env()`. That unblocked the fleet; it did not fix the class.

## The class of bug

`plexus` was a headless watcher box until 2026-08-20, when borg's PSU failed and
it became the human's workstation. From that morning, every job testmgr runs has
been inheriting a live desktop session:

| carried into every job | via |
|---|---|
| `DBUS_SESSION_BUS_ADDRESS` | `systemctl --user show-environment` |
| `DISPLAY=:0`, `WAYLAND_DISPLAY=wayland-0`, `XAUTHORITY` | same |

Verified on the watcher's own process (`/proc/<pid>/environ`). It is not a unit
bug: `systemd-run --user` is the recommended way to run long jobs on this box
(an un-tmux'd SSH kills a bare `&`), and the manager hands every one of them
that environment.

The measured consequence was `test/test_c_gtk_call.pas` hanging forever after
`gtk_init` — GTK's at-spi bridge reaching a session bus that did not exist on
this box until August 20th. Three days of native tiers spent their full hour on
it. **a11y is not the interesting part.** Anything that opportunistically talks
to a display, a session bus, a keyring, a portal or a notification daemon can
hang exactly the same way, and will look just as mysterious — because the repo
will not have changed.

## Why a blocklist is the wrong shape

`job_env()` now sets `NO_AT_BRIDGE=1` and `GTK_A11Y=none`. That is a symptom
fix, and the next one costs another three-day outage to find. The durable
answer is an **allowlist**: a test job should start from a minimal, declared
environment (PATH, HOME, LANG, the TESTMGR_* keys, TERM=dumb) plus whatever a
job explicitly asks for, and inherit nothing else — the same argument as
`stdin=DEVNULL`, one level up.

Note the dead end, already measured: `gsettings org.gnome.desktop.interface
toolkit-accessibility` is **false** on this box and the bridge runs anyway with
its own socket at `/run/user/1000/at-spi/bus`. Do not spend time there.

## Care needed

- Some jobs legitimately want a display: the `xvfb-run` ones set up their own,
  and `test/gui/**` may want the real one. `xvfb-run` supplies `DISPLAY` itself,
  so dropping the inherited value is right, but check the gui targets.
- The corpus/qemu jobs read a handful of environment keys — enumerate before
  stripping, and land it with the full matrix green rather than on a guess.
- Keep `job_env()`'s explicit a11y kills even after the allowlist exists; they
  cost nothing and document the incident.

## Gate

Track T's own full sweep, green on plexus **while a desktop session is logged
in** — that is the condition that makes this class visible at all, and it is now
the normal state of the box.
