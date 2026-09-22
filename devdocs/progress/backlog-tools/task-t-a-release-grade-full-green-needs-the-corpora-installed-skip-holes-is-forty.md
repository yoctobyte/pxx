---
slug: task-t-a-release-grade-full-green-needs-the-corpora-installed-skip-holes-is-forty
track: T
prio: 60
type: task
status: backlog-tools
found: 2026-09-22
found-by: frankh-c0
owner: ""
blocked-by: []
summary: 'A `full` tier IS green off borg as of 2026-09-22 -- plexus, qemu 10.2.1, 4904 PASS / 0 FAIL / 0 FLAKY / 46 SKIP, 1283.7s, `d03add15c` -- so neither tier''s never-green record was ever a statement about the tree. ONE THING NOW STANDS BETWEEN THAT AND GOAL 1''s "full green pin as release", AND IT IS NOT CODE: 40 of those 46 skips are ABSENT CORPORA, under the tier''s own banner reading "CORPUS MISSING -- 40 job(s) will SKIP, not run. A green verdict here does NOT cover them." Goal 1 wants `skip_holes == 0`, so a release candidate''s verdict does not mean what the goal needs until the corpora are present. THE SHAPE OF THE JOB, measured rather than assumed: `tools/install_lib_candidates.sh` is a FETCH, not a project -- a committed tool that curls pinned upstream versions into the gitignored `library_candidates/`, each with a PROVENANCE.md, refusing to run if that directory ever stops being gitignored. So this is an install step. TWO CONSTRAINTS MAKE IT NOT PURELY MECHANICAL AND BOTH ARE THE REASON THIS IS A TICKET: (1) only `zlib` is fetched today, 5.0 MB of a 24-candidate menu, and the missing set is `c-testsuite` (24 of the 40 jobs), `fpc-testsuite`, `fpc-rtl`, `lua`, `sqlite`, `cjson`, `fcl-json` and `external/synapse`; (2) THE ROOT FILESYSTEM ON PLEXUS IS AT 94% WITH 9.9 GB FREE, and the /tmp inode outage of 2026-09-07 -- which took the breadth instrument down for ten hours at 9% BYTES used -- is the standing precedent that a resource ceiling arrives as a cliff rather than a slope, so check `df -i` as well as `df -h` before and after. It also needs NETWORK from whichever host runs it, which is why it is worth naming rather than assuming. WHAT THIS TICKET DOES NOT CONTAIN, and the correction is recorded because a predecessor of this ticket was filed on it and REJECTED within the hour: the "fifteen job ids more red on qemu 10.2.1 than on 8.2.2" are NOT a backlog and NOT work. Every one of the fourteen with any reds had ALREADY ENDED before seven''s last report -- none was red in its final 20 reports -- because those rates are not per-run probabilities at all but single past EPISODES: `size_canary.py` is 189 reds in ONE contiguous run of 158, `test_libwriteln_parity.pas` is 86 consecutive reds inside one day. A rate computed over a time window is not a per-run probability, and the question that exposes it is whether the events are CLUSTERED or SPREAD. So the predicted cost of upgrading borg''s qemu from those rows is essentially ZERO, and the case for it is simpler than the trade earlier reported. WHAT WOULD RETIRE THIS TICKET: a `full` tier with verdict GREEN and `skip_holes == 0` on any host. WHAT WOULD RETIRE ITS NUMBERS: a re-check of `df -h`/`df -i` and of `ls library_candidates/`, both of which move without anyone touching this file.'
---

# A release-grade `full` green needs the corpora installed — `skip_holes` is 40

## What is already settled, so nobody re-derives it

- **`full` is green off borg.** plexus, qemu 10.2.1, 4904 PASS / 0 FAIL /
  0 FLAKY, 1283.7s, `d03add15c`. Earned **under contention** — another clone's
  testmgr shared the box, 2x timeouts, kills retried — which given the same
  night's load measurement makes 0 FLAKY across 4904 jobs a *harder* green than
  an idle one.
- **`native`'s chronic row was an emulator version difference**, not compiler
  work. Closed in
  `done/bug-t-native-s-red-is-one-row-and-full-s-is-ninety-four-so-they-are-different-problems.md`,
  which holds all of it.

## The job

**Install the corpora on whichever host publishes a release candidate, then
re-run `full` and check `skip_holes == 0`.**

```
tools/install_lib_candidates.sh c-testsuite fpc-testsuite fpc-rtl lua sqlite cjson fcl-json
```

**Check the disk first and afterwards, bytes AND inodes.** The precedent is
explicit: on 2026-09-07 seven died on **inodes at 9% bytes used** and took the
breadth instrument out for ten hours. `df -h` alone would have reported a
healthy box during the exact event.

**Note the recursion before it wastes anyone's time:**
`test-fpjson#src:tools/install_lib_candidates.sh` is **itself one of the 40
skipped jobs**, so the tool that closes the hole is inside the hole. That is
not a blocker — the script runs standalone — but a reader who only looks at the
skip list will think it is.

## The trap this ticket exists to disarm

**"The full tier is green" is the phrase that will get quoted without the
banner.** It already nearly was. The tier prints the qualification itself:

```
!! CORPUS MISSING — 40 job(s) will SKIP, not run.
!! A green verdict here does NOT cover them.
```

So when quoting that green, carry `4904/0/0/46` **and** the 40-job hole, in the
same breath. A green with a hole is progress and is not the goal.
