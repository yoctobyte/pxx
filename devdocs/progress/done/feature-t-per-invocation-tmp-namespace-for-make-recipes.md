---
summary: "The Makefile's ~3700 fixed /tmp/test_* output paths make two concurrent `make test*` runs on one box clobber each other; route them through a per-invocation temp dir"
type: feature
track: T
prio: 55
status: done
---

# Per-invocation temp namespace for the make test recipes

- **Type:** feature (Track T infra, enables real per-box parallelism) — **Track T**
- **Opened:** 2026-08-01. Filed from A+P+C+N.

## The problem

`tools/testmgr.py` isolates properly: every run gets `/tmp/testmgr-scratch-<pid>`
and tears it down afterwards. **The raw make recipes do not.** The Makefile
contains **3704** occurrences of fixed `/tmp/test_*` output paths:

```
/tmp/test_nilpy_gshadow26
/tmp/test_aarch64_args
/tmp/test_aarch64_args_x64
...
```

Two concurrent `make test-nilpy` / `make test` runs on one box write the same
files and read each other's outputs. The failure is a **false RED** (or, worse,
a false GREEN when the clobbering run happened to write the expected bytes),
and it is timing-dependent, so it looks like flakiness rather than a collision.

This matters more than it used to because `tools/gate.sh` shells out to raw
`make` for the suites — `gate.sh quick` runs `make test-nilpy` — so the gate
every track is told to use inherits the race that testmgr avoids.

It is also the second half of the "watcher + dev on one box" problem already
noted in the backlog; the first half is
[[bug-t-selfhost-build-uses-fixed-tmp-paths-colliding-across-clones]], which is
sharper (it corrupts the compiler, not a test output) and should land first.

## Fix

Introduce a single variable, e.g.

```make
PXX_TMP ?= $(shell mktemp -d /tmp/pxx-run-XXXXXX)
```

and rewrite `/tmp/test_` → `$(PXX_TMP)/test_` across the recipes. Mechanical:
3704 sites but ONE pattern, so it is a scripted rewrite plus a careful read of
the diff, not 3704 decisions. Keep `PXX_TMP` overridable so a caller can pin it.

**Landmine to respect:** testmgr rewrites absolute `/tmp` paths appearing in
expected output, and an expected output must never contain an absolute `/tmp`
path (see `devdocs/dev/gating-and-waiting.md`). Making the prefix vary per run
interacts directly with that rewrite — check the tests whose EXPECTATION
mentions a path before assuming the sweep is purely textual.

Do this incrementally per suite (nilpy, core, cross) rather than as one commit,
so a mistake is bisectable.

## Gate

Two concurrent `make test-nilpy` runs from two checkouts on one box both pass,
share no output file, and clean up after themselves. Then the same for the
other suites touched.

## CONSOLIDATED 2026-08-13 into the Track A ticket — duplicate, and mis-laned

This ticket and [[chore-makefile-testtmp-parameterize]] are the same job: route
the Makefile's fixed `/tmp` paths through one variable. That one is older
(2026-07-08 vs 2026-08-01), correctly filed on **Track A** — the Makefile is A's
file-ownership and A's gate, and CLAUDE.md scopes Track T to `tools/**` and
`tstate/**` "and nothing else". Everything here has been merged into it, its
prio raised 45 -> 55 to match, and the mechanical work de-risked:

- the sweep script, measured at **6755 rewrites, 4 pinned**;
- a **total verification protocol** — `make -n` across all 90 targets is
  byte-identical after the sweep (37825 lines, `diff` clean), which is stronger
  than the per-suite incremental landing this ticket asked for, and also proves
  the change is transparent to testmgr (it builds its job list from `make -n`);
- `make test-smoke TESTTMP=<scratch>` verified green end to end, self-host
  fixedpoint chain included;
- the **pinned set measured rather than assumed**: 63 source-hardcoded paths
  exist, only 3 are named in the Makefile, and testmgr's docstring citing
  `external '/tmp/liblazycasing.so'` is stale — that source now uses a bare
  soname.

**Two corrections to what this ticket proposed**, both worth carrying forward:

1. **`TESTTMP ?= /tmp`, not a per-invocation `mktemp -d` default.** The
   `mktemp` shape recommended above would break every testmgr job: testmgr
   privatizes by *prefix substitution*, so a nested default expands to
   `<scratch>/pxx-run-ab12/foo`, a directory nothing creates. Recipe paths must
   stay flat under `/tmp`; isolation is the caller's to request.
2. **The Gate as written cannot be met by this sweep.** 60 of the 63
   source-hardcoded paths are written by the test *binary* at runtime, not by
   the recipe (e.g. `test/test_nilpy_sqlite_crud.npy:7` opens
   `/tmp/test_nilpy_sqlite_crud.db`), across 40 files. No Makefile sweep reaches
   them and testmgr deliberately does not privatize them, so concurrent runs
   still share those files. That is a separate, smaller job.

The "Landmine to respect" note above — expected output must never contain an
absolute `/tmp` path — held up: no `.expected` file contains one, and the
expansion diff would have caught it.

## Log
- 2026-08-13 — resolved, commit PENDING-COMMIT.
