---
summary: "Enroll make lib-test + make demos in testmgr tiers — Track B's gate is invisible to tstate"
type: task
prio: 45
---

# Enroll lib-test and demos in the watcher

- **Type:** task (Track T — tools & testing)
- **Status:** backlog
- **Opened:** 2026-07-14
- **Filed by:** Track B, after finding `make lib-test` red (esptimer) with no
  tstate record of when it broke.

## The gap

Track B's entire gate — `make lib-test` (48 compile+output-assert steps: RTL
smoke, PAL cross under qemu, ESP object emission) and `make demos` (19
example compile-smokes) — runs only when a B agent types it. The watcher
covers core/threads/asm/C-conformance/cross/sqlite/lua but not one library
job beyond the `lib-fpc-clean` grep. Concrete cost today: the esptimer
lib-test step has been red for an unknown number of commits (pinned binary
predates the b360 emit-obj fix) and nothing recorded the first bad SHA.

## Pin-lag caveat (design point, not a footnote)

lib-test/demos build with `$(PXX_STABLE)` (the PINNED binary), not HEAD. So a
red has TWO causes: (a) a lib/examples change broke it — a normal regression;
(b) the pin is stale relative to lib/ expectations — a Track A "re-pin needed"
signal, exactly the esptimer case. The report format should make the compiler
identity visible (pin version/sha256 from `stable_linux_amd64/default/pin.log`)
so a triaging agent can tell (a) from (b) without re-deriving it.

## Scope

- New jobs `test-lib` (= `make lib-test`) and `test-demos` (= `make demos`,
  but demos currently prints FAIL without exiting nonzero — give it a gating
  mode or parse the output) in the `full` tier.
- qemu-user needed for the PAL cross steps — same host requirements as the
  cross jobs already in `full`.
- Record pin identity in the job result line (see caveat above).

## Done when

A commit that breaks a library smoke or a demo compile shows up as a tstate
NEW-RED with the pin identity attached; the esptimer-style silent red cannot
recur.
