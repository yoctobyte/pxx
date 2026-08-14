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

## 2026-08-14 — everything needed is built and tested; enrolment HELD on one Track B bug

Track B's gate now *can* be enrolled — it is one line in `TIERS["full"]`. It is
deliberately not that line yet, for a reason below.

### What was blocking it, and was not obvious

`split_jobs` collapsed all 824 expanded lines of `lib-test` into **one job**. Its
boundary is `COMPILE_RE`, which only knew `./compiler/pascal26` — but Track B
builds with `$(PXX_STABLE)`, the *pinned* binary, because B must never rebuild
the compiler. So a red would have said `lib-test#00 failed` without naming which
of 166 steps, which is not a regression signal.

Widened `COMPILE_RE` to know both spellings. **Verified inert before landing**:
every target currently in `TIERS` was split with the old and new regex and the
job list compared by name+source — **29 targets, all IDENTICAL, zero job
identity moved.** That check was not optional; renumbering jobs reads as mass
migration in tstate ([[bug-t-optdiff-positional-sharding-migrates-job-identity]]).

`lib-test` now yields **166 jobs**, correctly classed (162 unit, 2 qemu, 2
corpus), each attributed to its source.

### Corpus roots are no longer library_candidates-only

Two jobs need `external/synapse`, which nothing fetches and no Makefile guard
protects — so they FAILED rather than skipped. `CORPUS_ROOTS` now generalises
the existing self-skip to any corpus root, and the missing-corpus banner names
the root and the right fetch instruction per root.

Note the regex has **no leading word boundary**, deliberately: the path arrives
glued to its flag as `-Fuexternal/synapse`, so both `\bexternal` and
`[^\w]external` fail to match and every affected job stays FAILED. Two attempts
went that way before measuring it.

### Pin identity, per this ticket's own caveat

`report_pin_identity()` prints next to the banner whenever a pin-built target is
scheduled:

```
testmgr: pin=291 sha256=63390fe0bc9b9a4e (lib-test and demos build with THIS, not HEAD)
```

so a triaging agent can tell a Track B regression from a stale pin without
re-deriving it — which is exactly the esptimer case that filed this ticket.

### Measured: 163 pass, 2 skip, 1 fail

The one failure is why this is held.
[[bug-b-cstring-batch-gcc-oracle-does-not-build-on-gcc-14]]: `cstring_batch.c`
calls `memrchr` without `_GNU_SOURCE`, so its **gcc oracle** stopped compiling
at gcc 14 (implicit declarations became errors). The recipe discards gcc's
stderr *and* its exit status, then diffs against a missing binary and announces
`FAIL: cstring_batch differs from gcc` — naming pxx as the party that differs
when no comparison happened at all.

Enrolling today would therefore make the **full tier permanently RED on every
box with a modern gcc**, for something that is not a pxx defect. That is the
precise failure mode [[bug-t-three-network-tests-flake-and-cost-real-debugging-time]]
was just closed to remove, so it would be a poor trade. **Add `"lib-test"` to
`TIERS["full"]` the day that Track B fix lands.**

### `demos` is not attempted

Still blocked as this ticket originally described: it prints FAIL without
exiting nonzero, so it needs a gating mode or output parsing — and that is a
Makefile change, which is not Track T's ground.

## 2026-08-14 — ENROLLED. `lib-test` is in `TIERS["full"]`

The Track B blocker landed: `bug-b-cstring-batch-gcc-oracle-does-not-build-on-gcc-14`
is in `done/`, `test/cstring_batch.c` now defines `_GNU_SOURCE`, and — the part
that actually mattered for this tier — the recipe **checks gcc's exit status**
and prints `SKIP: cstring_batch (gcc cannot build the oracle: ...)` instead of
diffing against a binary that was never built and blaming pxx for the
difference. So the permanent-red risk this ticket held on is gone in both
directions: the oracle builds, and if it ever stops building again the job says
so about *gcc* rather than manufacturing a pxx red.

Measured before flipping the line, on plexus and against the current pin
(`pin=304 sha256=44ca47c950df2ae6`):

```
164/164 pass, 2 skip (corpus absent)
est_mem peak/est MB: corpus 49/400  qemu 26/256  unit 525/550
```

The 2 skips are the `external/synapse` jobs, correctly self-skipped and loudly
announced by `corpus_warning` rather than counted as green.

**Job identity: nothing moved.** Verified the way
[[bug-t-optdiff-positional-sharding-migrates-job-identity]] demands — every job
in every tier listed with the old and the new testmgr, compared by
tier+name+class:

| | jobs |
| --- | --- |
| before | 5528 |
| after | 5700 |
| removed or reclassified | **0** |
| added | 172 (166 lib-test + 6 pascal-conformance, all in `full`) |

So no red migrates and no phantom NEW-RED/FIXED pair is produced on the next
publish. `full` goes 2388 -> 2560 jobs.

The tier comment now also carries the pin-lag caveat this ticket opened with —
a lib-test red is EITHER a Track B regression OR a stale pin, and those route to
different tracks — because that is the one thing a triaging agent needs and the
one thing the job name cannot tell them.

### `demos` is still NOT enrolled, and that half stays open

Unchanged from the analysis above: `make demos` prints FAIL without exiting
nonzero, so it needs a gating mode or output parsing, and that is a **Makefile**
change — not Track T's ground. Filing it into Track B is the right move; this
ticket stays in backlog until that happens, since its title covers both.
