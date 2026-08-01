---
summary: "The self-host build writes fixed /tmp/pascal26-build|verify paths, so the watcher's dedicated clone and a dev checkout on the same box overwrite each other's in-flight compiler — /tmp is not per-clone"
type: bug
track: T
prio: 75
---

# The self-host build's fixed /tmp paths defeat the watcher's dedicated clone

- **Type:** bug (Track T infra, cross-process corruption) — **Track T**
- **Opened:** 2026-08-01, found while auditing why concurrency incidents keep
  recurring for dev agents. Filed from A+P+C+N: these are Track T's files.
- **Not proven to have caused a specific red.** The mechanism below is verified
  from the Makefile; attributing any particular phantom RED to it is a
  hypothesis, and a good first thing to check when triaging the open
  phantom-red family. Do not record it as the cause of one without measuring.

## The mechanism

`Makefile` lines 18-22 define the build's intermediates as **absolute, fixed**
paths:

```make
FPC_COMPILER            := /tmp/pascal26-fpc
BUILD_COMPILER          := /tmp/pascal26-build
VERIFY_COMPILER         := /tmp/pascal26-verify
BUILD_COMPILER_MANAGED  := /tmp/pascal26-managed-build
VERIFY_COMPILER_MANAGED := /tmp/pascal26-managed-verify
```

and a build round writes e.g. `/tmp/pascal26-build-r1`, `/tmp/pascal26-verify-r1`
(observed directly in build output).

The watcher runs in **its own dedicated clone** — that is the whole point of
the clone, to keep its state off a dev checkout. But **`/tmp` is not per-clone.**
Two checkouts on one box (watcher clone + dev checkout, or two dev agents) both
resolve `/tmp/pascal26-build-r1` to the same file. Concurrent self-host builds
therefore write each other's intermediates.

So the isolation the dedicated-clone design promises is real for the git tree
and absent for the build. That gap is invisible until two builds overlap, which
is exactly the configuration the project is moving toward (rely on T, keep
developing locally).

## Why this outranks the other temp-path issues

The sibling ticket [[feature-t-per-invocation-tmp-namespace-for-make-recipes]]
covers the ~3700 fixed `/tmp/test_*` paths in the test recipes. Those corrupt a
TEST result. These five corrupt **the compiler binary being verified for the
self-host fixedpoint** — the gate that blesses the stable binary every other
track builds on. A false fixedpoint result is a worse failure than a false test
result, and it is silent.

## Fix

Route the five through a per-invocation directory, e.g. a `PXX_TMP ?=` variable
defaulting to a `mktemp -d` (or `/tmp/pxx-build-$(shell echo $$PPID)`), with the
existing names underneath it. Small and self-contained — unlike the test-recipe
sweep, this is five definitions plus their use sites.

Keep it overridable so the watcher can pin its own root explicitly.

## Gate

Two concurrent `make compiler/pascal26` runs from two different checkouts on one
box both converge and both produce a byte-identical fixedpoint, with no shared
intermediate file between them. Verify by racing them deliberately, not by
reasoning about it.
