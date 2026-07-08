---
prio: 45
---

# Makefile: parameterize hardcoded /tmp test paths ($(TESTTMP)) — concurrent gates corrupt each other

- **Type:** chore/infra (Makefile test recipes — shared ground). Track A.
- **Found:** 2026-07-08 by Track T: a local `--tier full` gate and the borg
  watcher's gate ran concurrently; both self-host chains write the same
  literal `/tmp/pascal26-self/next/fixedpoint`, and the local run failed
  byte-identity with a clean tree (interleaved binaries).

## State
Makefile test recipes hardcode ~1700 distinct `/tmp/<name>` outputs (3037
occurrences). Any two concurrent test runs on one box race on all of them.

**testmgr already contains the runtime fix**: it rewrites literal `/tmp/`
to a private per-run scratch dir when executing job scripts, so concurrent
testmgr runs (dev gate + watcher, or two watchers) are isolated by
construction. NOT covered: plain `make test` / `make test-smoke` run by a
human or agent while a watcher gate is active on the same box.

## Wanted
Mechanical parameterization: `TESTTMP ?= /tmp` at the top, recipes use
`$(TESTTMP)/...`. Behavior-identical by default; then `make test
TESTTMP=$(mktemp -d)` (or exporting it in CI docs) makes manual runs safe
too, and testmgr can drop its string rewrite. Sed-able but sweeping — needs
a careful pass + full gate + self-host, and should land in a quiet window
(every track's recipes are touched).

## Gate
`make test` + self-host byte-identity green with TESTTMP unset AND with
TESTTMP set to a scratch dir; testmgr full tier green.
