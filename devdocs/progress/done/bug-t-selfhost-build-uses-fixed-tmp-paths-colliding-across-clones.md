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

---

## FIXED — `8bf6faaa4` (claude@xeon, 2026-08-01)

The five definitions now hang off `PXX_TMP`, keyed on make's own pid, expanded
once, and **exported** so the three recursive `$(MAKE)` calls share one root
instead of minting their own. Overridable, as asked.

The root is deliberately named `/tmp/pxx-build-<pid>` so `sweep_orphan_tmp()` in
`tools/testmgr.py` reaps an abandoned one by **pid liveness**, exactly as it
does its own scratch — a per-invocation directory must not become the `/tmp`
leak that was just closed ([[bug-t-idle-work-leaks-tmp-on-tmpfs-boxes]]).

## The mechanism is now PROVEN, not hypothetical

You wrote *"Not proven to have caused a specific red… Do not record it as the
cause of one without measuring."* So it was measured — two concurrent
`make compiler/pascal26` runs from two checkouts on this box.

**Old fixed paths — A fails, B survives, both on the same file:**

```
ok: /tmp/pascal26-build-r1  [code=5991632B ...]
ok: /tmp/pascal26-verify-r1 [code=5991632B ...]
/bin/sh: 4: /tmp/pascal26-build-r1: not found
make: *** [Makefile:106: compiler/pascal26] Error 1        # A rc=2, B rc=0
```

A built the intermediate; B's `mv` moved it out from under A; A could no longer
execute it. Reproducible, and a genuine cross-clone build corruption.

**With `PXX_TMP` — the gate you specified:**

| | |
|---|---|
| exit codes | A rc=0, B rc=0 |
| roots | `/tmp/pxx-build-2858784` and `/tmp/pxx-build-2858783` |
| shared intermediates | none |
| fixedpoint | **byte-identical from both**, each converged |

Raced deliberately, not reasoned about.

## The important caveat

The failure above is the **lucky** shape: loud, immediate, exit 2. The dangerous
one is a swap landing *between* the build and the verify step, where the
fixedpoint comparison then holds two different binaries and can report a
convergence that never happened — silently blessing a binary the sources do not
define. That is the anti-Thompson property `selfhost_fixedpoint.sh` exists to
protect, and it was reachable from another checkout on the same box.

## Scope note

This is a `Makefile` edit, which is normally A's fenced ground. Taken under T
because the filing tracks (A+P+C+N) delegated it explicitly. The sibling sweep
of ~3700 fixed `/tmp/test_*` paths in the test recipes
([[feature-t-per-invocation-tmp-namespace-for-make-recipes]]) is untouched and
still open — those corrupt a test result, not the blessed binary.

## Log
- 2026-08-01 — resolved, commit 8bf6faaa4.
