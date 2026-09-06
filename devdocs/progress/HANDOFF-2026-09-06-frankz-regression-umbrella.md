# frankZ — regression umbrella, 2026-09-06 night

**A DATED RECORD OF WHAT ONE SESSION HELD, NOT INSTRUCTIONS.** CLAUDE.md wins
over every sentence here. Do not widen a gate on this file's authority and do
not "fix" it later — if it contradicts the tree, the tree is right.

**frankZ is the REGRESSION UMBRELLA. The Z is a session name, NOT Track Z
(Zig).** Two peers made that error tonight, hours apart, and both acted on it
before being corrected. If you inherit this name, correct it on introduction.

## Held: nothing

Tree clean, everything pushed. There is no stash, no patch and no parked work.

## What I was about to do next, and why

**`tools-devtest#00` — full tier says `**TIMED OUT**`, and a timeout is not a
red.** I had just taken the local numbers and had not yet used them:

    148 devtest files, 405.1s total wall on plexus
    4 reds: host_dev_lib_skip, npy_cross_target_expectation,
            progress_near, testmgr_hardcoded_tmp

frankB reached the same four names independently on a different box, which is
corroboration that fails differently rather than two runs of one instrument.

**The open question is which of two things the timeout is**, and they need
different fixes: cumulative wall against a scaled deadline
(`DEFAULT_DEADLINE = 3600.0`, `MAX_JOB_DEADLINE_FRAC = 0.5`, `testmgr.py:600`
and `:618` — so a single job may be capped well below 3600s), or one devtest
that actually hangs on seven and not here. **405s local is nowhere near 3600s,
so the cumulative story does not obviously work** — which is exactly why it
needs measuring rather than assuming. Nobody should write "the devtests got
slow" into a ticket until that fork is settled.

It matters now because it is one of the last full-tier reds under a release
bar, and because a TIMED OUT job publishes no per-file verdict, so the four
reds above are invisible in the report that matters.

## Full-tier reds as I last measured them (`c69b52b`, 18:02Z)

Read with section attribution — `## FIXED` and `## STILL-RED` both contain rows,
and a bare `grep '^- '` silently merges them. That mistake is mine, tonight.

- `size-canary` — needs an A+S decision, not mine
- `test-emit-obj` ×3 — frankA's fixes (`fc000b076`, `d058a3dae`) POSTDATE this
  report; its reds say nothing about them
- `test-zlib` — `2523453c4` postdates it likewise
- `test-fpjson` — no corpus in this checkout; fetching one is outbound
- `test-core#test_promoint_bitwise` — already `FIXED` by the 18:19Z native run
- `tools-devtest#00` — the timeout above
- `test-xtensa#…test_cross_record.pas@3` — **cleared by `0a96caf54`**, confirmed
  absent on seven

## The three instrument errors I made tonight, and the guard each needs

Worth more than the fixes, because each cost real time and none of them errored.

1. **`find / -maxdepth 4 -name tstate`** returned nothing, and I concluded the
   archive was not on this box. It is at `devdocs/progress/tstate/`, depth 5.
   *Guard: a negative from a bounded search is a statement about the bound.*
2. **`@N` in a job key indexes JOBS, not Makefile occurrences.** I measured
   `#138` and published a "not reproducible" for `#147`. The discriminator was
   printed in the report I was holding — its log showed `code=491372B` and every
   program I built came out `196460B`. *Guard: resolve a key with
   `testmgr --list`, never by counting lines in the file it appears to name.*
3. **`grep '^- '` on a tstate report** merged `## FIXED` rows into the red list,
   and I nearly filed a regression for a row that had just been fixed.
   *Guard: attribute every row to its heading.*

The common property is not carelessness. **Each instrument answered a different
question without erroring**, which is CLAUDE.md's own standing rule met three
times in one session by someone who spent that session writing it up.

## Standing exculpation warning

I published a "not reproducible" that was wrong. **An exculpation is the class
that never gets revisited** — a green nobody re-checks and a "not reproducible"
nobody re-runs are the same object, a verdict that stops work. Mine was caught
only because a peer asked an unrelated question whose answer required opening
the archive. That is not a repeatable mechanism.
