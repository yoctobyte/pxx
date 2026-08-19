---
track: T
prio: 45
type: chore
blocked-by: []
summary: "Five of the 33 `tools/*devtest*.py` guards fail on a clean master, and one of them is a real discipline violation rather than test rot: `tstate_reader_devtest` names five tools reading tstate by filesystem path that are not in ALLOWED. Nothing runs any of them — they are in no Makefile target — so they have been rotting unobserved."
status: done
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

## Resolved 2026-08-19 by Track T (plexus-T)

All five fixed, and the family wired so it cannot rot unobserved again.

### The four drift cases

| devtest | what had drifted |
| --- | --- |
| `bench_timing_devtest` | `_timed_run` grew a fifth field (`task_mhz`); now unpacks by slice, so the next addition does not break it for a reason unrelated to what it measures |
| `twatch_gone_key_devtest` | `reg_open()` dropped its `fixed` parameter — the merged status map answers on its own. Six calls updated |
| `twatch_close_stubs_devtest` | two faults: the fixture lacked `report["jobs"]`, which `close_stub_tickets` came to need; and two `reg_open` calls still passed `fixed` **positionally**, so the list landed in `authoritative` and the status map in `gone` — every job read as gone and the cascade closed for a reason unrelated to the test |
| `devtest_autotriage` | it set `A.PROGRESS` to a fixture but let `cited_tickets` read the **real repo** source, so its expectation depended on the current header of an unrelated test — which was rewritten to cite a different ticket. Fixture is now self-contained |

**One of those was passing vacuously**, which is worse than the failures and was
only visible once the file was opened: *"no citation for a test that names no
ticket"* passed because the named file did not exist, not because it cited
nothing. Both sources are now real files in the fixture.

### The fifth was not rot — it was the guard working, and it found a live bug

`tstate_reader_devtest` named five tools reading tstate by filesystem path.
Judged one at a time rather than waved through as a group:

- **four are devtests** (`devtest_pin_shadow`, `devtest_pin_verify`,
  `devtest_pinstatus`, `devtest_wedge_on_own_writes`) that join tstate onto a
  root **they just created under tempfile**. No live watcher tree to be stale
  about — the same argued case as the already-listed `twatch_close_stubs_devtest`.
  Added to `ALLOWED` with per-file reasons.
- **`autotriage.py` was a real violation and is FIXED, not allowlisted.** It read
  `devdocs/progress/tstate/<host>.json` out of the **working tree**. A watcher
  clone stands detached at the sha under test for most of every cycle, and
  triaging open regressions inside that clone is a perfectly normal thing to do
  — which is exactly when that read is wrong. It now reads off the ref
  (`git show origin/master:...`) by default, with `--rev ''` as the explicit
  worktree opt-in a dev checkout needs for tstate it has not pushed. Its
  `ALLOWED` entry covers only that opt-in.

That is the ticket's own argument landing: a guard nobody runs is not a guard,
and the moment this one was run it produced a real finding rather than noise.

### Wired: `make tools-devtest`, enrolled in `limited` + `full`

- New Makefile target, fails on the first red, one recipe line so `split_jobs`
  keeps it whole. Measured **30.1s under testmgr**, 36 guards green.
- `limited` + `full`, **not** `native` and not `quick`. Same reasoning the tier
  table already applies to `test-nilpy` and `test-uforth`: native is what dev
  boxes gate their pushes on, and these guards protect the **harness** rather
  than the product, so they must not buy coverage with the one number T is not
  allowed to inflate. T's own gate is `--tier full`, so T's changes still meet
  them.
- Job-list diff across the change: **exactly one new key** (`tools-devtest#00`),
  zero renames, zero reclassified — the before/after comparison a job-composition
  change is supposed to carry.

### Deliberately excluded from the gate: `bench_timing_devtest`

Its subject **is** timing precision — it measures a 50 ms polling-grid artifact —
so it is load-sensitive by construction, and this box runs the watcher by design.
Measured: failed once in ~7 runs at load 13, then 6/6 at load 6. A flaky gate on
a shared box manufactures exactly the false reds Track T exists to remove. It
stays fixed, and runnable by hand, and out of the tier, with the reason recorded
at the exclusion rather than in a ticket nobody re-reads.

**Nothing new was filed:** no breakage was uncovered beyond the five, and the one
real bug found (`autotriage`) is T's own tool and was fixed inline rather than
routed.

## Log
- 2026-08-19 — resolved, commit PENDING-COMMIT.
