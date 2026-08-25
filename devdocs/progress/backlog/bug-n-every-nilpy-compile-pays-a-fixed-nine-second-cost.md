---
track: N
prio: 60
type: bug
blocked-by: []
summary: "Measured 2026-08-25 (pin v374, this box): compiling `print(\"hi\")` costs 8.92s; compiling `begin end.` costs 0.25s. The ~8.7s is a FIXED per-invocation constant — it does not scale with program size — and it is pure user CPU, not I/O. It is ~29% of the entire test matrix's CPU (805 .npy jobs x 8.7s ~ 7000 of 24219 cpu-s) and it is 9 seconds on every NilPy user's hello-world."
---

# Every NilPy compile pays a fixed ~9-second cost

Found by Track T while measuring where the test matrix's wall-clock actually
goes, for the "testing overhead is 95% of development time" question. It is by a
wide margin the largest single lever in that number, and unlike every tiering
proposal it costs **no coverage at all** — it is the same tests, faster.

## The measurement

Pinned compiler `stable_linux_amd64/default/pinned` (v374), plexus, otherwise
idle-ish box:

| source | wall |
| --- | --- |
| `print("hi")` (`.npy`) | **8.92s** |
| `begin end.` (`.pas`) | **0.25s** |
| `test/test_nilpy_forin.npy` | 8.79s |
| `test/test_nilpy_c_pointer.npy` | 9.28s |
| `test/test_nilpy_str_format_conversion_and_containers.npy` | 8.88s |

Two things make this a constant rather than a workload:

- **It does not scale with the program.** A one-line `print` and the real test
  files land within half a second of each other. Whatever costs 8.7s is being
  done *before or regardless of* the user's source.
- **It is compute, not I/O.** Sampling `/proc/<pid>/stat` during the compile
  shows `utime` climbing ~100 jiffies/s (100% of one core) for the whole run,
  with `wchan` at 0 throughout. So this is not header hunting or disk.

Per-job means from the watcher's learned metrics agree, over thousands of runs:
`.npy` jobs mean **13.93s** (median 12.56s), `.pas` jobs mean **1.49s** (median
1.08s), `.c` jobs mean 1.62s. The gap is the constant, not a few slow tests.

## Why it is worth a 60

- **~29% of the whole test matrix.** 805 distinct `.npy` job identities x ~8.7s
  of pure overhead is ~7000 cpu-seconds, against 24219 cpu-seconds for every
  measured job identity in the store. Removing it shrinks every tier that
  contains NilPy — including `limited`, which is what a box with no qemu runs.
- **It is why NilPy sits in no fast tier.** `test-nilpy` was kept out of
  `native` because enrolling it took the fast verdict from ~104s to ~235s
  (see `TIERS` in `tools/testmgr.py`). That trade exists *because of this
  constant*: at `.pas` per-test cost the whole NilPy suite would fit in the
  fast verdict, and the frontend would get dense per-push coverage instead of
  a canary.
- **It is a user-facing number too.** Nine seconds to compile hello-world is
  what a person evaluating NilPy measures first, and it is the one benchmark
  they will run before reading any docs.

## Where it probably is (NOT verified — do not take this as the cause)

The obvious hypothesis is that the NilPy runtime / builtins are lowered from
source into **every** compile, where the Pascal path uses something already
built. `uses pyrt` is not a unit (`unit source not found`), so the runtime is
not a Pascal unit a user can name — it is inside the compiler. That is a
hypothesis from two timings and nothing else.

**Measure before you conclude** (`devdocs/dev/debugging-playbook.md`): `perf` is
blocked on this box by `perf_event_paranoid` and `gdb -p` by `ptrace_scope`, so
neither a profile nor a stack sample is in this ticket. That is exactly the gap
the owning lane should close first — a profile of `pxx tiny.npy` will name the
function in one run, and every route from here without one is guessing.

Repro, ~10 seconds:

```
printf 'print("hi")\n' > /tmp/tiny.npy && printf 'begin end.\n' > /tmp/tiny.pas
time stable_linux_amd64/default/pinned /tmp/tiny.npy /tmp/o
time stable_linux_amd64/default/pinned /tmp/tiny.pas /tmp/o
```

## Lane

Filed as **N** because the asymmetry is between frontends and NilPy is the slow
one. If the profile lands in shared unit/builtin compilation rather than in
`pyparser`/Python-to-IR lowering, it is an **A** ticket and should be re-filed —
`T owns the tool, never the bug`, and this ticket does not presume which lane
owns the fix, only that it is not T's.

Gate when fixed: `make test-nilpy` green + self-host byte-identical. Worth
re-measuring the two timings above in the resolve note, since the whole ticket
is a number.
