---
summary: "lib_net_v6only, lib_sockets and lib_platform_esp each pass or fail run-to-run with the SAME compiler, so a gate.sh lib RED and two cross-sweep A/B deltas in one night were all noise that had to be disproved by hand"
type: bug
track: T
prio: 45
---

# Three network-ish tests flake, and the flakes read as regressions

- **Type:** bug (test infrastructure) — Track T (owns the tooling; the tests
  themselves are Track B's `test/lib_*.pas`)
- **Status:** done
- **Opened:** 2026-08-05
- **Found by:** hitting all three in one session while landing unrelated fixes.

## The evidence

Each was disproved by running the SAME test repeatedly with the SAME compiler,
and separately with the pinned stable, and watching the verdict flip:

| test | how it showed up | disproof |
| --- | --- | --- |
| `lib_net_v6only` | `tools/gate.sh lib` went **RED**, then GREEN on a plain re-run | it builds with `$(PXX_STABLE)`, so an uncommitted compiler change cannot be the cause |
| `lib_sockets` aarch64 | appeared as an A/B delta in `lib_cross_sweep` | 2 runs each: pinned DIFF/DIFF, HEAD DIFF/SAME — flips independently of the compiler |
| `lib_platform_esp` i386/arm32/aarch64 | appeared as three A/B deltas | 3 runs each: **SAME every time for both compilers**, yet it had DIFF'd in two earlier sweeps |

`tools/lib_cross_sweep.sh`'s own header already warns that a network- or
thread-using test differing under qemu-user is not by itself evidence. That
warning is right and it is not enough: the flake still lands in the report
looking exactly like a regression, and the only way to tell is to re-run by
hand, which is minutes each time and has to be repeated by every agent who hits
it.

## Why it matters more than three tests

A gate that is red for reasons unrelated to the change teaches everyone to
discount red. Tonight's cost was ~20 minutes of A/B work to prove three
findings were noise — during which a *real* regression (`GetBox.Poke;`, caught
by Track T's full tier) was in flight.

## Options, roughly in order of preference

1. **Make them deterministic.** Fixed ports are the usual culprit — bind to
   port 0 and read back the assigned port, so two concurrent runs (a gate and a
   sweep, which happened here) cannot collide. Worth checking first whether
   that is the whole story for `lib_net_v6only` and `lib_sockets`.
2. **Retry-once-then-fail in the harness**, with the retry *reported*. A silent
   retry hides a genuine intermittent bug; a reported one distinguishes "flaked
   and passed" from "passed".
3. **Quarantine list** — a named set the sweep and `lib-test` run but report
   separately, so they never mix with real signal. Cheapest, and the least
   honest of the three.

`lib_platform_esp` may be a different animal: it is not obviously a network
test, and it flipped while being SAME in six consecutive controlled runs. Worth
looking at what in it is time- or environment-dependent before assuming ports.

## Gate

Track T: `tools/testmgr.py --tier full` green for tooling changes. If the fix
lands in the tests themselves that is Track B — `tools/gate.sh lib` — and the
proof is running each 10x with an unchanged compiler and getting one verdict.

## DONE 2026-08-14 — harness half fixed; two root causes found, neither is the network

The ticket's option 1 ("make them deterministic — fixed ports are the usual
culprit") was half right, and the half it got wrong is the interesting one.

### `lib_platform_esp` — not a network test, not a timing flake

It calls every `Pal*` entry point with **fd 0**, which is stdin. So it measures
the launch environment. Same binary, four stdin kinds, four different outputs —
and with fd 0 *closed* its own `PalSocket()` is handed descriptor 0, after which
every later call operates on a real socket instead of stdin. Full table in the
Track B ticket.

**This is Track T's to fix at the harness level**, and it is fixed:
`Manager.launch` now passes `stdin=subprocess.DEVNULL`. Jobs previously
inherited testmgr's own stdin — a terminal under `make`, a pipe under a gate,
whatever systemd hands the watcher — so the *same test on the same commit*
answered differently depending on how the run was started. That is a general
determinism hole, not an esp-specific one; this test just happened to be the
one sensitive enough to show it.

### `lib_sockets` — fixed port, exactly as the ticket guessed

`const PORT = 28744`, so two concurrent runs collide. That is the gate-plus-sweep
overlap that opened this ticket.

### `lib_net_v6only` — no defect found, and said so rather than fixed

**20 consecutive runs, unchanged binary, one identical output.** It already binds
port 0 and reads it back, so the fixed-port hypothesis never applied. Its single
observed flake stays **unexplained**. Filed as such rather than
speculatively "fixed", because a change with no reproduction is indistinguishable
from a change with no effect.

### Where the rest goes

Both real defects are in `test/lib_*.pas`, which is Track B's — see
[[bug-b-two-lib-tests-are-environment-dependent-by-construction]], which carries
the repros. Options 2 (reported retry) and 3 (quarantine list) are **not**
implemented and should not be: with two of three explained by construction and
the third unreproducible, a retry mechanism would now be hiding defects rather
than absorbing noise.

### Gate

`tools/devtest_job_stdin.py` — drives the REAL `Manager.launch` (not a
reconstruction, since the thing asserted is one keyword a refactor could drop)
with the parent's stdin pointed at a regular file and at a pipe, and checks the
child sees `/dev/null` both times. Includes a **control** that spawns the old
way and confirms the probe would actually have caught the previous behaviour —
without it, a probe that always passes proves nothing.

`tools/gate.sh quick` GREEN; all eight Track T devtests pass.

## Log
- 2026-08-14 — resolved, commit c409b2774.
