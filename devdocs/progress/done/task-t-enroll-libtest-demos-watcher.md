---
summary: "Enroll make lib-test + make demos in testmgr tiers — Track B's gate is invisible to tstate"
type: task
prio: 45
---

# Enroll lib-test and demos in the watcher

- **Type:** task (Track T — tools & testing)
- **Status:** done
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

## 2026-08-16 — the pin-lag caveat fires for real, and the SAME red changes category

This ticket opened with a design point: a `lib-test` red has two causes, (a) a
lib/examples regression and (b) a pin stale relative to lib/'s expectations,
and they route to different tracks. That has now happened to a single red,
which is worth recording because it is the case the caveat was written for.

`lib/rtl/contnrs.pas` failed to compile
([[bug-p-a-class-method-does-not-shadow-a-builtin-of-the-same-name]] — a class
method named `Delete` did not shadow the builtin). At the time it was
unambiguously **(a)**, verified by running both compilers:

```
pin v341  -> FAIL contnrs
HEAD      -> FAIL contnrs      identical, so not pin lag
```

Track P fixed it in `12c078883`. Re-run immediately after, with the compiler
rebuilt:

```
pin v341  -> FAIL contnrs                              <- unchanged
HEAD      -> lib-units: 139 units compile              <- fixed
```

**The same job, the same error text, now means the opposite thing.** It is no
longer a Pascal-frontend bug for Track P; it is a stale pin, and the action is a
**re-pin by Track A** (`make stabilize-fast && make pin`). No amount of Track B
or P work will clear it, and `lib-test` stays RED — taking its other 166 jobs
with it — until the pin moves.

That is exactly why `report_pin_identity()` prints the pin on the banner:

```
testmgr: pin=341 sha256=fcf011d76990a729 (lib-test and demos build with THIS, not HEAD)
```

**The rule, for whoever triages the next one:** run the failing lib step against
BOTH `$(PXX_STABLE)` and `compiler/pascal26` before filing. Same failure = a
real lib/frontend bug. Fails on the pin, passes on HEAD = the fix has landed and
the pin has not, so file nothing and ask Track A to re-pin. It costs two
commands and it is the difference between a ticket and a no-op.

Worth noting the window is structural, not a mistake: Track A pins deliberately
rather than continuously (`stabilize-fast` blocks other tracks while it runs),
so every frontend fix that lib/ depends on has a period where HEAD is green and
the pin is not. Track T's job is to label that period correctly, not to shorten
it.

## 2026-08-16 — `lib-test` is GREEN, 167/167, and the onion is fully peeled

```
testmgr: pin=344 sha256=47836e63248f1404 (lib-test and demos build with THIS, not HEAD)
  167/167 pass, 2 skip (corpus absent), 1 flaky (passed on retry)
testmgr: GREEN
```

First fully green `lib-test` since enrolment. The chain it took, in order, each
layer invisible until the one above it cleared:

1. **Enrolled** 2026-08-14 — before this, Track B's whole gate ran only when a B
   agent typed it.
2. **`crtl-map` stale** — `compiler/crtl_names.inc` had not been regenerated
   since crtl gained ten functions ([[regression-lib-test-crtl-reachability]],
   Track C, `9860b8bf7`).
3. **`contnrs` did not compile** — a class method named `Delete` did not shadow
   the builtin ([[bug-p-a-class-method-does-not-shadow-a-builtin-of-the-same-name]],
   Track P, `12c078883`; the same guard shape turned out to affect **eight**
   soft intrinsics, not one).
4. **A regression in the fix for something else** —
   [[regression-test-core-test-local-typed-const]], bisected to `3ed3e2653`,
   fixed in `467a4e5da`.
5. **Re-pin** — the fixes were in HEAD while `lib-test` builds against
   `$(PXX_STABLE)`, so the red survived the fix until the pin moved (the
   pin-lag section above).

Five layers, four of them real defects, none of which anything else was going to
surface. That is the enrolment paying for itself, and it is the concrete answer
to the question this ticket opened with — *the esptimer lib-test step has been
red for an unknown number of commits and nothing recorded the first bad SHA.*

**The `demos` half remains open** and unchanged: it prints FAIL without exiting
nonzero, so it needs a gating mode or output parsing, which is a Makefile change
and not Track T's ground. This ticket stays in backlog until that lands.

## 2026-08-17 — the `demos` half is DONE too, without the Makefile change it seemed to need

This ticket held `demos` out for days on one premise: *"it prints FAIL without
exiting nonzero, so it needs a gating mode or output parsing — and that is a
Makefile change, which is not Track T's ground."*

The premise was half right. It **is** a Makefile change if you make `demos`
gate — and that would overturn a deliberate decision, stated in the recipe
itself:

```
echo "(demos is a dashboard, not a gate; FAILs -> file a ticket)"; exit 0
```

with its neighbour `c-interop-devtest` repeating it: *"This intentionally exits 0
for candidate-library gaps; keep `lib-test` as the green gate."* Track B chose
that, and changing it from Track T would be the wrong lane deciding.

**So take the verdict from the OUTPUT and mark the job ADVISORY** — both halves
entirely inside testmgr, no Makefile touched:

- `demos_job()` runs `make demos`, echoes it for the log, and fails only if a
  `^  FAIL  ` line appears. (`grep -q` alone would have inverted the verdict;
  the pipeline preserves output and negates the match.)
- `j.advisory = True`, so a broken demo is a **NOTICE** for Track B in tstate
  rather than a red gating every other lane's push — exactly the status the
  recipe assigns it. The mechanism already existed for `fpc-bootstrap`.

That delivers this ticket's actual "Done when" — *a commit that breaks a demo
compile shows up in tstate* — without the policy change it assumed was required.

### It found a real one on its first run

```
  NOTICE   demos#00   corpus   87.0s
  testmgr: GREEN          <- advisory: reported, not gating
```

34/35 demos build; `examples/mandelbrot/mandelbrot_gui.pas` does not, and has
not since it landed on 2026-07-20. Filed as
[[bug-b-mandelbrot-gui-demo-does-not-build-missing-gtk3-c]] with a verified
one-line fix. Note the tier stayed **GREEN** while reporting it, which is the
whole point of advisory.

### Both halves of this ticket are now enrolled

| | status |
| --- | --- |
| `lib-test` | in `TIERS["full"]` since 2026-08-14, now 167/167 |
| `demos` | in `TIERS["full"]` as an advisory job, 2026-08-17 |

Resolving.

## Log
- 2026-08-17 — resolved, commit 7bcaacf9e.

## 2026-08-17 — the last 2 SKIPs are closed; `lib-test` coverage is now complete

Every report this ticket produced ended `167/167 pass, 2 skip (corpus absent)`,
and I quoted that line repeatedly without closing it. The two were:

```
lib-test#src:test/lib_synapse.pas
lib-test#src:test/lib_synapse_transitive_unit.pas
```

They skipped because `external/synapse` was absent from the watcher's clone —
and the reason nobody fetched it is that testmgr's own corpus warning said it
**could not be fetched by script**. That was false, and false from the day it
was written: `tools/install_externals.sh` has fetched synapse since 2026-06-07.
Fixed in the same pass (per-tree fetch hints, `CORPUS_FETCHERS`).

With the message corrected, closing them was one command:

```
tools/install_externals.sh        # in both clones
lib-test#src:test/lib_synapse*.pas  ->  2/2 pass
```

Fetched into **both** `/home/neo/pxx` and the watcher's `/home/neo/trackt-watch`
— the second is the one that matters, since tstate's coverage is what other
lanes read. The corpus is gitignored, so the watcher clone's git state is
unchanged and the daemon needed no restart: this adds a precondition, it does
not edit the clone.

**tstate now records no SKIPs for `lib-test` on plexus**, so a green there
covers what it claims to. That was the one remaining gap between "the tier is
green" and "the tier ran everything", which is the distinction this ticket's own
`corpus_warning` exists to make loud — and it had been quietly true against us
for the whole enrolment.
