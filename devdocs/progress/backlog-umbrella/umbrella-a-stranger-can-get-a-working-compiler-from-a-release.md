---
slug: umbrella-a-stranger-can-get-a-working-compiler-from-a-release
title: "A stranger downloads a release and ends up with a working compiler"
track: T
prio: 55
type: umbrella
blocked-by: [feature-release-checksums-repro, decide-release-signing-key-custody, bug-t-pin-verify-and-requested-verify-publish-a-verdict-with-no-manifest, bug-t-the-documented-build-path-never-enumerates-what-it-needs]
created: 2026-09-06
summary: "GOAL, not a unit of work. Owner, 2026-09-06: 'project goal, let's slowly prepare for a release.' The target is not a tag and not a document -- it is a person who has never seen this repo getting a compiler that works, from an artefact they can verify. SLOWLY is part of the instruction: this ranks steadily in the background, it does not displace development. Attach whatever an ATTEMPT breaks on; do not pre-populate it from the backlog by guessing."
---

# A stranger downloads a release and ends up with a working compiler

**Owner, 2026-09-06:** *"project goal, let's slowly prepare for a release."*
Earlier the same night, standing down the beta 0.1 sprint: *"this was a good
exercise though, let's keep practising for a real first beta release."*

## What the target is

Not a tag, not release notes. **A person who has never seen this repo obtains an
artefact, verifies it is the artefact we published, and gets a compiler that
compiles their program.** Every part of that sentence is separately testable and
none of it is testable by reading the backlog.

## Why prio 55 and not higher

**Only the owner sets an umbrella's prio; 55 is my reading of "slowly" -- move it
if the reading is wrong.** It ranks its chain steadily without displacing the 80s
and 85s. Two reasons it does not need to be higher:

- **`umbrella-one-full-tier-run-with-no-red-tier` is prio 85 and already carries
  the "is it green" half.** A release wants a verified rollback target and so
  does that umbrella; ranking both high double-counts one goal. Release quality
  inherits from there, not from here.
- This umbrella owns **packaging, provenance and the first hour** -- the
  dimension nothing else ranks.

## The three blockers, from an ATTEMPT

Attached because the 2026-09-06 attempt broke on them, not because they matched
a grep:

- **`feature-release-checksums-repro`** (blocked) -- an artefact nobody can
  verify is not a release.
- **`decide-release-signing-key-custody`** (U, prio 25) -- deliberately parked:
  the private-key half is human-only and **an agent must not originate a
  credential.** Its agent-work half is already re-filed, so this blocks the
  publish step and nothing else.
- **`bug-t-pin-verify-and-requested-verify-publish-a-verdict-with-no-manifest`**
  -- the two verification paths that most need a per-row manifest produce none.
  A release grade nobody can read row-by-row is a number, not evidence.

## Already MET, and worth defending as a property

Measured 2026-09-06 by frank-subcoord, both halves of build-from-clean green:

- **`make bootstrap` is green** -- fpc 3.2.2 seeds our source in 16.6s, the
  result builds and verifies, `cmp` IDENTICAL, 54.6s total. Two
  mutually-consistent-but-wrong compilers pass `make compiler/pascal26`,
  `gate.sh quick` and the pin; they do not pass this.
- **The FPC-seeded binary was byte-identical to the pin-derived one** at that
  tree. So **a stranger who does not trust our pin can rebuild it from FPC and
  compare shas.** That is the release property, stronger than "bootstrap works",
  and it is what this umbrella should not lose.
- Alpine container, git and make only, no bash/fpc/gcc, musl: builds, same sha.

## What the attempt found that is NOT attached

Each is fixed or belongs to another chain; recorded so the next attempt does not
re-derive it:

- **A bash-less box silently disarmed the stamp guard.**
  `tools/compiler_srchash.sh` was `#!/usr/bin/env bash`; absent bash it does not
  run, the stamp gets an empty srchash, and the recipe compares empty to empty
  and **passes vacuously** -- restoring in full the failure `01dd27dd1` exists to
  prevent. Fixed `79264f396`: POSIX sh, hash unchanged, **and the recipe now
  refuses an empty hash rather than comparing it.** An empty result means "could
  not measure", never "measured and they match".
- A licence check that reported no licence in a repo with four licence files
  (`ls LICENSE* COPYING* || echo ...`: `COPYING*` matched nothing, `ls` exited
  non-zero, the `||` fired).
- `test/wasm/check_all.sh` kept a **hand-maintained** checker list, so two new
  guards would have run never while the suite printed 42 green. Fixed
  `fa4d9c43f`.
- Two wasm32-only silent defects found while both wasm32 suites were fully green
  (`d58828d8c`, `8157808b2`). Carried by pin v407, not by v406.
- A `pxx.skip` row that kept a defect out of the very population its own guard
  was written to sample.

**The pattern is the deliverable: every one was an instrument answering a
different question, and what surfaced them was reading the project as a stranger
would.** That costs nothing and needs no release.

## Known untested step

The container had git and make **installed by hand**. A stranger's box may have
neither. That is the one remaining gap in build-from-clean and it is small.

## How to grow this

**By attempting the target.** Cut a candidate artefact, hand it to a machine that
has never built pxx, follow only what the published instructions say, and file
what breaks in the order it broke. What the attempt never touches was not
blocking a release. An umbrella with no blockers means nobody has attempted the
cell -- information, not missing paperwork.

`devdocs/dev/release-notes-beta-0.1-draft.md` is the rehearsal's draft:
incomplete, review unfinished, kept deliberately. A starting point, not a
specification.

## 2026-09-06, later — NO LIVE HOST HAS EVER PRODUCED A CLEAN FULL RUN

Measured by frankZ, corrected by frankH, confirmed independently, landed
`521b5ab1d`. It bears directly on this umbrella because a release wants evidence
of a green matrix and **there is currently no machine that has ever produced
one.**

  borg     newest clean 2026-07-31   last row of any kind 2026-07-31
  xeon     newest clean 2026-08-04   last row of any kind 2026-08-04
  plexus   newest clean 2026-08-26   last row of any kind 2026-08-30
  seven    none, ever                last row of any kind 2026-09-06, live

589 shas in the archive have a full run with no RED, and **all 589 are
historical.** `90892318c94c`, cited since 2026-09-02 as "the most recent full
green", is plexus's LAST clean run and eleven days old. Everything live rests on
seven, which has never produced one.

**This is not evidence the goal is unreachable** — seven went 9 reds -> 8 -> 5 ->
5 -> 3 in one evening, which argues the other way. What it rules out is a
specific plan: **any release criterion that assumes a second host can supply the
green is assuming a host that stopped reporting a week ago.**

**And the corrected number is the more useful finding.** The original count, 47,
came from `reports/*.md` — 2069 curated digests — when the archive is
`runs-<host>.ndjson` at 5530 rows. A subset. So the query answered *"shas that
got written up"* rather than *"shas that ran"*, **and it did not error.** The
per-host stop dates were invisible at 47 and are the whole finding at 589.

**A related structural fact, from frankH, worth carrying into any release
criterion:** one of tonight's three reds was self-inflicted — `85c8c1bf8` landed
GREEN under `gate.sh quick`, which does not run `tools-devtest#00`. **The
per-fix gate every seat is asked to run cannot see that job**, so reds arrive in
the full tier from changes that were green by every measure their author had.
Any plan that reasons about the red count reaching zero has to account for a
source of new reds that no author can see at commit time.
