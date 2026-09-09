---
slug: bug-t-six-real-program-jobs-are-in-no-tier-so-they-never-run
track: T
prio: 65
type: bug
status: backlog
owner: ""
created: 2026-09-09
found-by: frankuser
tags: [testmgr, tiers, corpus, coverage, silent-hole]
blocked-by: []
summary: "SIX real-program jobs are in NO TIER: test-duktape, test-quickjs, test-chess-perft, test-sqlite-parity, test-fpc, test-wasm32. Their Makefile targets exist, their corpora ARE installed on seven (duktape, quickjs, chess, sqlite, plus fpc-rtl and fpc-testsuite all present under library_candidates/), and no tier ever invokes them -- so they have produced ZERO verdict rows in any host archive, ever, and can rot indefinitely without anything going red. This is the THIRD and FOURTH instance of a hole testmgr.py documents twice in its own comments directly above the TIERS dict: test-nilpy was in no tier until 2026-08-01, hiding 238 of 309 .npy files, and test-uforth until 2026-08-08, when `grep -c uforth tools/testmgr.py` answered 0. Both notes are still there, three lines above six more of the same thing. TIER SIZES: quick 1, native 6, limited 19, full 40, slow 1, opt 1."
---

# Why this outranks a normal coverage gap

A job that FAILS is loud. A job that SKIPS says so in the report. **A job in no
tier produces no row at all**, so every instrument that reads the archive —
`twatch --status`, the regression bisector, coverage counts, and any human
asking "what do we test against" — is silent about it in a way indistinguishable
from the job not existing.

Measured today while building a "what pxx compiles" summary: the six were read
as *"target exists, never graded"*, which was true and which I could not
explain. The explanation is not that the tier skipped them; it is that **no tier
ever asks.**

# The precedent is in the file, three lines up

`tools/testmgr.py` carries two comments immediately above `TIERS`:

- *"test-nilpy: MAINLINE and gated ... but it was in no tier at all — so 238 of
  the 309 .npy files the Makefile compiles were invisible to the watcher and
  `make test-nilpy` could be RED while the full tier reported GREEN (measured
  2026-08-01)."*
- *"test-uforth: same hole test-nilpy was in, found 2026-08-08 —
  `grep -c uforth tools/testmgr.py` was 0."*

Two is a smell, three is a design flaw; this is six more. **Do not fix this by
adding six names.** The names are the symptom. Nothing today can answer *"which
`test-*` targets exist that no tier names?"* except a person deciding to ask,
and the two prior fixes both were a person deciding to ask.

# The fix that closes the class

A guard that enumerates `^test-[a-z0-9-]+:` from the Makefile, subtracts the
union of every tier's job list, and **fails on a non-empty remainder** with an
explicit opt-out list for targets deliberately outside the tiers (there are
legitimate ones — `test-quick` is its own tier, cross/qemu jobs have their own
placement rules, and a target may be a helper). The opt-out list is the place
the decision gets recorded instead of being an absence.

**That guard has this repo's favourite failure mode built in**, so give it a
positive control: it must FAIL on a fixture Makefile carrying an unlisted
target. A guard over an empty remainder passes forever and certifies nothing.

# Placement, once the class is closed

Not automatic. Each of the six needs a tier chosen on cost, and the comments
above `TIERS` record the rule: **native is what dev boxes gate pushes on and is
the one number T must not inflate** — enrolling ~300 NilPy jobs there took the
fast verdict from ~104s to ~235s. `limited`/`full` is where uforth and nilpy
landed for exactly this reason. Measure each job first; do not bulk-add to
`full` either.

# Provenance

Found while checking why six jobs had no archive rows before writing them into
an owner-facing summary — the check was "what would this be if it were false".
Corpora presence verified on seven directly (`library_candidates/`), tier
membership by parsing `TIERS` out of `tools/testmgr.py`.
