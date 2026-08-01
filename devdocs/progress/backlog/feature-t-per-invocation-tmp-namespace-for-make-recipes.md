---
summary: "The Makefile's ~3700 fixed /tmp/test_* output paths make two concurrent `make test*` runs on one box clobber each other; route them through a per-invocation temp dir"
type: feature
track: T
prio: 55
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
