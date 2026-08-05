---
summary: "lib_net_v6only, lib_sockets and lib_platform_esp each pass or fail run-to-run with the SAME compiler, so a gate.sh lib RED and two cross-sweep A/B deltas in one night were all noise that had to be disproved by hand"
type: bug
track: T
prio: 45
---

# Three network-ish tests flake, and the flakes read as regressions

- **Type:** bug (test infrastructure) — Track T (owns the tooling; the tests
  themselves are Track B's `test/lib_*.pas`)
- **Status:** backlog
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
