---
track: T
prio: 55
type: bug
status: backlog_new
blocked-by: []
found: 2026-08-30
found-by: frank-optimize, fixing regression-test-core-test-opt-store-reload
summary: "npy_cross_target_expectation_devtest.py ratchets duplicated expectations for .npy sources only, though its own COMPILE_RE already matches .pas and .c. The very next divergence was a .pas test duplicated into the SAME two targets the guard was written about, and it cost a p70 regression ticket and a live red on master. Widening the filter naively does not work — the natural population is full of legitimate cross-target asymmetry — but a keyed sub-population of 137 native identical-invocation sources has 15 deliberate exceptions and would have caught this one."
---

# The duplicate-expectation ratchet is `.npy`-only, and the first escape was a `.pas` test

## What happened

`bug-t-89-nilpy-expectations-are-duplicated-across-two-targets-with-nothing-keeping-them-in-sync`
(done, 2026-08-30) built exactly the right guard for exactly the wrong population.
`tools/npy_cross_target_expectation_devtest.py` ends its scan with

```python
MULTI = {s: t for s, t in BY_SOURCE.items() if s.endswith(".npy") and len(t) > 1}
```

while the scanner feeding it already matches all three source kinds:

```python
COMPILE_RE = re.compile(r"\$\(COMPILER\)\s.*?(test/[A-Za-z0-9_./-]+\.(?:npy|pas|c))\s+...")
```

The data was in the instrument and one predicate threw it away.

**Same day, same Makefile block, one file extension over.** `10c869750` added
`reord`/`reord2` rows to `test/test_opt_store_reload.pas` and updated the
`test-nilpy` copy of its expectation (labels `.1`/`.2`, Makefile ~line 851). The
`test-core` copy (labels `.3`/`.4`, ~line 11215) kept the short golden, and
`test-core` went red on plexus and seven, stayed red from 06:57Z to 08:45Z, was
auto-filed as a p70 regression, mistracked to P, retracked to A, and dispatched
to a session — for two missing lines of `printf`. That is the exact cost curve
the original ticket predicted, arriving before the ink dried.

The escape is worth naming precisely, because it is not "we forgot `.pas`":

> The ratchet was scoped to the population that had been **measured** (111 `.npy`
> sources, 0 drift) rather than to the **mechanism** (a Makefile with two copies
> of one expectation thousands of lines apart). The mechanism does not read file
> extensions.

## Why the naive widening is wrong, with numbers

Measured at `780ec9f7c` + this fix. Dropping the `.npy` filter and keeping the
guard's own source-keying:

| population | multi-target sources | divergent |
| --- | ---: | ---: |
| `.npy` | 111 | 0 |
| `.pas` | 176 | 144 |
| `.c` | 7 | 6 |

144 findings on day one is the report that teaches everyone to scroll past it —
the failure mode the original ticket explicitly refused. Almost all of it is
legitimate: a cross-target row compares a qemu run against the x64 binary, so the
two targets' payloads *must* differ.

## The sub-population that is actually ratchetable

Key on **(source, compile invocation with the `$(TESTTMP)` output name normalised
out)**, and keep only blocks where neither the compile line nor any payload names
a cross target (`--target`, `run_target.sh`, `qemu`, `wine`):

| | count |
| --- | ---: |
| native, >1 target, identical compile line | **137** (111 `.npy`, 25 `.pas`, 1 `.c`) |
| divergent expectations | **15** |

And all 15 are deliberate asymmetry, not drift — one target asserts a weaker form
of the same thing:

```
test/test_pyeval_m1.pas    [test-core test-nilpy]
   test-core   "$$(tail -1 .../OUT.log) $$(grep -c '^ok  ' .../OUT.log)" "ALL PASS 23"
   test-nilpy  "$$(.../OUT | tail -1)"                                   "ALL PASS"

test/test_tthread_sync.pas [test-quick test-threads]
   test-quick   "$$(.../OUT | tail -1)"  "TTHREAD SYNC OK"
   test-threads "$$(.../OUT)"            "$$(printf 'sync=200 ...\nTTHREAD SYNC OK')"
```

(12 `test_pyeval_*.pas` of one shape, `test_mutex`/`test_tthread_sync` of another,
`csystem_libs_granular_math_b112.c` of a third.) So the shape is the one the
existing devtest already uses for `KNOWN_NAME_COLLISIONS`: **ratchet 122, freeze
15 with the reason written down.** `test_opt_store_reload.pas` was in the 137 and
divergent before this fix; it is not after it, which is the check that the key
selects the right thing.

## Suggested work

1. Replace the `.npy` filter with the native/identical-invocation key above.
2. Freeze the 15 in a `KNOWN_ASYMMETRIC_EXPECTATIONS` dict — **value = the reason**,
   not just the name, so the sixteenth cannot be added without someone reading why
   the fifteen are there.
3. Keep `t_the_population_is_still_there()`'s instrument-guard and raise its floor
   to the new population, for the same reason it exists: a scan that silently stops
   matching reports zero drift forever.

Numbers above are reproducible from the Makefile alone (no build), so this is
cheap to re-measure before starting — do that rather than trusting the table, the
population moves with every added row.

**Not proposed:** de-duplicating the expectations into shared variables. That is the
same `decide-*` the original ticket declined to fold in, and it is still a design
call about whether `test-core` should re-run these sets at all.

## Gate

Track T's own full-tier sweep, green. The devtest itself runs in milliseconds
against the Makefile and needs no compiler.

## Aside, free with this ticket

`.claude/hooks/no-full-suite.sh` matches on command TEXT, so writing this ticket
via a bash heredoc was refused for quoting T's own gate command inside prose. The
hook cannot distinguish running a command from writing about one. Harmless here
(the file went in through the Write tool) but it will keep firing on anyone
documenting the gate, which is exactly the population you want writing it down.
