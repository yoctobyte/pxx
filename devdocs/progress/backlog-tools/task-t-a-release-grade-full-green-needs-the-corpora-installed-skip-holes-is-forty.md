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
summary: 'A `full` tier IS green off borg as of 2026-09-22 -- plexus, qemu 10.2.1, 4904 PASS / 0 FAIL / 0 FLAKY / 46 SKIP, 1283.7s, `d03add15c` -- so neither tier''s never-green record was ever a statement about the tree. ONE THING NOW STANDS BETWEEN THAT AND GOAL 1''s "full green pin as release", AND IT IS NOT CODE: 40 of those 46 skips are ABSENT CORPORA, under the tier''s own banner reading "CORPUS MISSING -- 40 job(s) will SKIP, not run. A green verdict here does NOT cover them." Goal 1 wants `skip_holes == 0`, so a release candidate''s verdict does not mean what the goal needs until the corpora are present. THE SHAPE OF THE JOB, measured rather than assumed: `tools/install_lib_candidates.sh` is a FETCH, not a project -- a committed tool that curls pinned upstream versions into the gitignored `library_candidates/`, each with a PROVENANCE.md, refusing to run if that directory ever stops being gitignored. So this is an install step. TWO CONSTRAINTS MAKE IT NOT PURELY MECHANICAL AND BOTH ARE THE REASON THIS IS A TICKET: (1) only `zlib` is fetched today, 5.0 MB of a 24-candidate menu, and the missing set is `c-testsuite` (24 of the 40 jobs), `fpc-testsuite`, `fpc-rtl`, `lua`, `sqlite`, `cjson`, `fcl-json` and `external/synapse`; (2) DISK, MEASURED 2026-09-22 AND WITH THE DENOMINATOR QUESTION SETTLED: `library_candidates/` is a subdirectory of the checkout and `/home` is NOT a separate mount on plexus, so the target volume IS the root one -- `/dev/sdc3`, 156G, **9.9 GB free at 94%**, which makes bytes the binding resource against a 24-candidate menu. INODES ARE THE MIRROR OF THEIR OWN PRECEDENT AND THAT IS WHY BOTH NUMBERS ARE HERE: 1328744 of 10436608 used, 13%, 9.1M free -- healthy -- whereas on 2026-09-07 seven died on INODES AT 9% BYTES USED and took the breadth instrument down for ten hours. Neither figure predicts the other; run both and see which is binding on the host in front of you. `/tmp` is a separate 94G volume at 7%, so staging there is possible where the target directory has no room. It also needs NETWORK from whichever host runs it, which is why it is worth naming rather than assuming. WHAT THIS TICKET DOES NOT CONTAIN, and the correction is recorded because a predecessor of this ticket was filed on it and REJECTED within the hour: the "fifteen job ids more red on qemu 10.2.1 than on 8.2.2" are NOT a backlog and NOT work. Every one of the fourteen with any reds had ALREADY ENDED before seven''s last report -- none was red in its final 20 reports -- because those rates are not per-run probabilities at all but single past EPISODES: `size_canary.py` is 189 reds in ONE contiguous run of 158, `test_libwriteln_parity.pas` is 86 consecutive reds inside one day. A rate computed over a time window is not a per-run probability, and the question that exposes it is whether the events are CLUSTERED or SPREAD. SO THE COST SIDE OF UPGRADING BORG''s QEMU IS UNMEASURED, NOT ZERO, AND THE DISTINCTION IS THE CORRECTION -- this ticket said "essentially ZERO" until 2026-09-22: fourteen closed episodes, none red in its final twenty reports, is an ABSENCE OF EVIDENCE about the next one and not a demonstration that nothing breaks. The sentence that goes to the owner is one-directional and hedged: borg''s row fails 549 of 550, nothing in the archive says the upgrade would break anything, and the cost side is unmeasured rather than shown absent. No design fork in it. WHAT WOULD RETIRE THIS TICKET: a `full` tier with verdict GREEN and `skip_holes == 0` on any host. WHAT WOULD RETIRE ITS NUMBERS: a re-check of `df -h`/`df -i` and of `ls library_candidates/`, both of which move without anyone touching this file.'
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

**The target filesystem, measured 2026-09-22 rather than assumed — and the
mount question mattered.** `library_candidates/` is a plain subdirectory of the
checkout, so on plexus it lands on whatever carries `/home/neo/frankH`, and
**`/home` is NOT a separate mount here**: `df -h .` and `df -h /` both answer
`/dev/sdc3`. So the root figure is the right denominator, which was not obvious
before checking.

```
/dev/sdc3   156G  138G  9.9G  94% /          <- bytes: the binding resource
/dev/sdc3   10436608 inodes, 1328744 used, 9107864 free, 13%   <- healthy
/dev/sdd2    94G  6.5G   87G   7% /tmp       <- a SEPARATE volume, and roomy
```

Present today: **5.0 MB, all of it `library_candidates/zlib`.**

**THE INODE CHECK IS THE MIRROR OF ITS OWN PRECEDENT HERE, WHICH IS WHY BOTH
NUMBERS BELONG IN THE TICKET.** On 2026-09-07 seven died on **inodes at 9%
bytes used** — a tmpfs — and took the breadth instrument out for ten hours;
`df -h` alone would have called that box healthy during the exact event. On
plexus it is the other way round: inodes are at 13% with 9.1M free and **bytes
are the ceiling at 94%**. Neither figure predicts the other, and running both
is what tells you which one is binding on the host in front of you. Re-measure
both before and after; a `/tmp`-based staging step has 87 GB available and the
target directory does not.

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
