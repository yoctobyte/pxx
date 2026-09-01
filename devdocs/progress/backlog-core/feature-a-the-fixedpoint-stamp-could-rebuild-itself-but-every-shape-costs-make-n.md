---
track: A
prio: 30
type: feature
status: backlog
found: 2026-09-01
found-by: frankA
owner: ""
blocked-by: []
summary: "The stale-stamp bug now STOPS loudly (527837d3a) instead of printing a false success; making it REBUILD by itself is the remaining half and both implementations were measured out. Recursing with $(MAKE) from the verify recipe breaks `make -n` outright (GNU make executes a $(MAKE) line under -n, so the dry run deleted the stamp and exited 2). A .PHONY-backed witness file works in a real run but makes `make -n compiler/pascal26` always report the loop as planned, because -n must assume a PHONY prerequisite updates its target. Needs a shape that does neither, or a decision that the loud stop is enough."
---

# The stamp could rebuild itself, and every shape I tried costs `make -n`

Split out of
[[bug-a-the-mandatory-fixedpoint-step-reports-success-from-a-stale-stamp]],
whose loud-stop half landed as `527837d3a`. **Nothing is broken today**: a stamp
written for other sources is refused with a one-line recovery, and running that
line rebuilds correctly. This ticket is only about removing the manual step.

## Why it is not just "add a witness file"

Both obvious shapes were built and measured, not reasoned about.

**1. Detect in the verify recipe and recurse.** `rm -f $(COMPILER_STAMP);
$(MAKE) $(COMPILER_STAMP)` inside the `$(COMPILER)` recipe. GNU make
**executes** a recipe line containing `$(MAKE)` even under `-n`, so
`make -n compiler/pascal26` ran the detection, **deleted the stamp** and exited
2. Measured: stamp empty afterwards, rc=2.

That is not a small blast radius. `make -n` is load-bearing here: testmgr's
`make_dry_run()` builds its job list from it, and `.claude/hooks/
no-full-suite.sh` exempts dry runs precisely because they execute nothing.

**2. A `.PHONY`-backed witness file** holding the source hash, rewritten only
when the hash changes, with `$(COMPILER_STAMP)` depending on it. Correct in a
real run — measured: the honest no-op stays 0.7s and does **not** rebuild, and
the planted stale pair rebuilds to the true fixedpoint by itself. But under
`-n`, make must assume a PHONY prerequisite updates its target, so
`make -n compiler/pascal26` **always** reports the loop as planned. The row
`an honest stamp for the CURRENT sources does not re-plan the loop` in
`tools/selfhost_stamp_devtest.sh` is what caught it.

## What a fix would have to do

Give `$(COMPILER_STAMP)` a real (non-PHONY) prerequisite whose mtime tracks
"the sources last actually differed", without a rule that make must assume
updates it. Candidates not yet tried:

- a parse-time `$(shell ...)` that refreshes the witness. Accurate under `-n`,
  but it runs on **every** make invocation of **any** target in this repo
  (~0.22s each) and it writes a file during `make -n`, which is its own
  violation of "-n runs nothing".
- teaching whatever writes the stamp to also `touch` the witness, so the
  witness needs no rule at all — but then nothing refreshes it when the sources
  change outside a build, which is the case this is about.

## The honest alternative

**Decide the loud stop is enough** and close this. The failure it replaced was
silent; what is left is one printed command. Three agents lost time to the
silent version in one day and none would to this one. That is a legitimate
outcome, not a cop-out — record it here rather than leaving the ticket open
forever.

## Positive control for whatever lands

`tools/selfhost_stamp_devtest.sh` already carries both arms:
`a stamp written for OTHER sources is refused, not read back as success` must
become "rebuilds", and `an honest stamp for the CURRENT sources still verifies`
must stay green — plus a row asserting `make -n compiler/pascal26` mutates
nothing and does not plan the loop when the stamp is honest.
