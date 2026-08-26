---
track: T
prio: 55
type: chore
summary: "Every systemd-run --user job on plexus inherits a full desktop session — DBUS_SESSION_BUS_ADDRESS, DISPLAY=:0, WAYLAND_DISPLAY, XAUTHORITY — because systemctl --user show-environment carries them and the watcher's own /proc/<pid>/environ has them all. a11y was the symptom that hung a job for three days; anything that opportunistically talks to a display or session bus can hang the same way. Strip the environment for test runs instead of blocklisting symptoms one variable at a time."
status: done
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

---

## RESOLUTION 2026-08-26 — allowlist, with the pass-through rule inverted

`job_env()` is now an allowlist. A job gets `PATH HOME USER LOGNAME SHELL PWD
TMPDIR LANG LANGUAGE TERM CC CXX AR LD MAKEFLAGS MAKELEVEL MFLAGS
LD_LIBRARY_PATH PKG_CONFIG_PATH SOURCE_DATE_EPOCH`, the `PXX_ TESTMGR_ LC_
QEMU_` families, and `NO_AT_BRIDGE`/`GTK_A11Y` — **11 keys in practice**, down
from the full login environment. The 24 session/desktop variables measured on
this box are gone, including `XDG_RUNTIME_DIR` (the at-spi autolaunch path the
ticket warns about) and an unrelated third-party API key that had been reaching
every test subprocess in every tier.

### The first draft of the pass-through rule was backwards

The ticket asks for "whatever a job explicitly asks for". The obvious reading —
*a job that runs `Xvfb`/`xvfb-run`/`gui_shot` is a display job, give it the
session* — is **wrong, and wrong in the dangerous direction.** Those tools
**start a display of their own** and hand it to the child. The three GTK jobs in
`test-core` all run under `xvfb-run -a`, and one of them is
`test_c_gtk_call.pas` — the job that hung for three days. Matching on the tool
name would have re-admitted the session bus to precisely the jobs whose at-spi
hang started this ticket.

So pass-through triggers **only on a literal reference to a session variable in
the job's own recipe text**. That is a direct dependency read rather than a
guess about behaviour: if a recipe says `$DISPLAY` it needs `DISPLAY`; a program
that reaches a display without its recipe saying so is exactly the case being
stopped. Measured across the full tier: **zero** jobs reference one, so
everything runs session-free today, and the rule is there for the first job that
legitimately needs it.

### The mirror-image failure mode, and what prevents it

Stripping an environment risks the opposite of what it fixes — a job losing
something it needs and going red with no cause visible in its log. Three things:

- **the run announces it**, in the same log as the verdicts it could change:
  `job environment is an ALLOWLIST — dropped 24 session/desktop variable(s) …`
  plus the jobs that kept the session, or `all run session-free`;
- **`TESTMGR_INHERIT_ENV=1`** restores inheritance for one run (still forcing
  the a11y switches off — the hatch is for debugging the allowlist, not for
  re-hanging). Implemented, not merely documented;
- **`testmgr_job_env_devtest.py`**, 23 cases, pinning both directions: the
  session family is gone and has not crept back, what a build-and-run needs is
  still present, an `xvfb-run` job is NOT given the session, a job naming
  `$DISPLAY` IS and actually receives it, the hatch works, and the report names
  variables and jobs rather than a bare count.

### Verified, not assumed

The ticket's own measurement is that unsetting the bus **alone makes it worse**
(at-spi autolaunches one and blocks there), so this had to be tested rather than
reasoned about:

| job | under the stripped environment |
| --- | --- |
| `test_c_gtk_call.pas` — the 3-day hang | **rc=0, 0.22s** |
| `test_c_gtk_types.pas` | rc=0, 0.18s |
| `test_c_gtk_window.pas` (runs `gtk_main`) | rc=0, 1.20s |
| `test_c_gtk.pas` | rc=0 |
| `testmgr --tier quick` | **26/26 pass, GREEN** |

75 guards green; self-host fixedpoint clean.

### Not done

`NO_AT_BRIDGE`/`GTK_A11Y` are kept rather than removed. They are now redundant
for the bus-address path but not for a GTK that finds a bridge another way, they
cost nothing, and removing a working guard to prove a new one is a bad trade.
The dead end the ticket records (`toolkit-accessibility` is false and the bridge
runs anyway) was not revisited.

## Log
- 2026-08-26 — resolved, commit PENDING-COMMIT.
