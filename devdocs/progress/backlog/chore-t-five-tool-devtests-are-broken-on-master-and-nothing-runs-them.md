---
track: T
prio: 45
type: chore
blocked-by: []
summary: "Five of the 33 `tools/*devtest*.py` guards fail on a clean master, and one of them is a real discipline violation rather than test rot: `tstate_reader_devtest` names five tools reading tstate by filesystem path that are not in ALLOWED. Nothing runs any of them — they are in no Makefile target — so they have been rotting unobserved."
---

# Five tool devtests are broken on master, and nothing runs them

Filed 2026-08-19 by Track T (plexus-T), from running the whole family while
gating an unrelated `twatch.py` change. Measured on a clean checkout of
`761fb3843` with no local modifications — **28 pass, 5 fail**:

| devtest | failure | kind |
| --- | --- | --- |
| `tstate_reader_devtest` | `autotriage.py`, `devtest_pin_shadow.py`, `devtest_pin_verify.py`, `devtest_pinstatus.py`, `devtest_wedge_on_own_writes.py` read tstate by path and are not in `ALLOWED` | **the guard firing correctly** |
| `bench_timing_devtest` | `testmgr._timed_run` returns 5 values, the test unpacks 4 | API drift |
| `twatch_gone_key_devtest` | `reg_open()` has no `fixed=` parameter any more | API drift |
| `twatch_close_stubs_devtest` | `close_stub_tickets` does `report["jobs"]`; the fixture has no such key | API drift |
| `devtest_autotriage` | `cited_tickets` returns `[]` where the test wants one citation | behaviour drift |

**The first row is the one that matters and it is not test rot.** That guard
exists because reading a watcher clone's worktree as if it were current state
caused four separate bugs in one day (`devdocs/dev/track-t.md`, "a watcher
clone's worktree is HISTORY"). Its own docstring says the ALLOWED list "is short
and argued on purpose — a guard that is muted as noisy is not a guard." It is
now failing rather than muted, which is worse: nobody is reading it at all.

**Why they rotted: nothing executes them.** `grep -n devtest Makefile` finds only
the five `*.sh` ones (`c-interop`, `tls-openssl`, `tls13-handshake`, `truststore`,
`tls-native-seam`). The 33 Python ones are run by hand, by whichever agent
remembers, which over months means the ones nobody touches drift and stay
drifted. Every one of them is self-contained and fast — the whole family, the
five failures included, runs in well under three minutes.

## Shape

1. Fix the five. The four drift cases are each a signature update; the ALLOWED
   one is a judgement call per tool — route it through
   `materialize_tstate()`/`states_at()`, or add it with a reason.
2. **Then wire them**, or step 1 happens again. A `tools-devtest` target that
   runs `tools/*devtest*.py` and fails on the first red, enrolled in a tier T
   already runs. They are cheap enough that `quick` could carry them, which
   would put them in every dev's inner loop rather than only in T's.

Not urgent — none of these guards protects a live gate today, which is exactly
why it can wait and exactly why it will keep rotting until someone wires it.
