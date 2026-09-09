---
slug: bug-t-the-tstate-reader-guard-is-enforced-in-a-tier-no-per-fix-gate-runs
track: T
prio: 45
type: bug
status: backlog
owner: ""
created: 2026-09-09
found-by: frank-seven
tags: [tools, devtest, guard, gate, tstate]
blocked-by: []
summary: "tools/tstate_reader_devtest.py refuses any tool that reads tstate by filesystem path unless it is in ALLOWED. Its only failure mode is SOMEONE ADDED A FILE, and it runs in tools-devtest, which gate.sh quick does not run -- so the author lands green and the red exists only in the full tier, hours later, attributed to their sha. THIS HAS NOW HAPPENED THREE TIMES and the ALLOWED table records two of them in its own entry text: twatch_idle_tier_try_devtest.py (85c8c1bf8, 2026-09-06, broke it ~40 minutes) and twatch_autopin_devtest.py (fc2ce3d02, 2026-09-09, this one). Every instance was a SYNTHETIC FIXTURE under its own tmp dir -- the legitimate pattern -- so every fix was a one-entry addition and none was a real defect. A guard that fires only on new files, is enforced only where no per-fix gate looks, and whose correct resolution is always 'add a row' is catching authors rather than defects."
---

# The shape

The guard is right and the pattern it catches is right. What is wrong is WHERE
it is enforced and WHAT the author is given to notice it with.

- Fires only when a file is ADDED. Nothing an existing tool does can trip it.
- Enforced in `tools-devtest`, and **`gate.sh quick` does not run that job**.
  So the sequence is always: author gates green, lands, pushes; the full tier
  goes red hours later at their sha; a bisect attributes it correctly and a
  seat spends a pass rediscovering that the fixture was fine all along.
- The correct fix has been "add one entry to `ALLOWED`" **three times out of
  three**. Zero of the three were a tool actually reading live tstate.

# Why the reason string made it worse this time

`tools-devtest#00`'s recipe (`Makefile:33297`) is a `for f in tools/*devtest*.py`
loop that `printf`s each NAME BEFORE running it. The stored tstate reason is
that stream truncated at ~120 chars, so it always names the same first four
scripts regardless of which one failed. On `fc2ce3d02` it named
`twatch_toolchain_devtest.py`, `twatch_verify_request_devtest.py`,
`verify_assertions_devtest.py` and `whoholds_devtest.py` — **all four pass, on
both boxes, and none was ever implicated.** The actual failure was
`tstate_reader_devtest.py`.

That is a reason string that is CORRECT ABOUT SOMETHING ELSE — it faithfully
reports the loop's progress — and it points four names away from the defect.
A seat that runs the four named scripts gets green and concludes the row is
stale. **This seat did exactly that**, from plexus, and was wrong.

And the file under suspicion passes *as a devtest* while *causing* another
devtest to fail, so running it proves nothing. The two facts compose into a
row that cannot be checked by the obvious method.

# Three candidate fixes, cheapest first

1. **Make the reason name the failing script, not the loop's progress.** Print
   the name AFTER the result, or capture per-script rc and report only reds.
   This is small and it is the one that would have saved this pass. It fixes
   the misdirection but not the lateness.
2. **Run `tstate_reader_devtest.py` in `gate.sh quick`.** It is one fast Python
   script over a file list, not a tier. Then the author sees it before landing,
   which is the entire complaint. Measure its cost first — quick is ~30s and
   defended.
3. **Make the guard self-describing at the point of failure**: have it print the
   exact `ALLOWED` stanza to paste, with the fixture-vs-live distinction spelled
   out, so the fix does not require reading the file's history to learn that a
   synthetic fixture is legitimate.

1 and 3 are independent of 2 and both are cheap. Do not reach for
"just relax the regex" — the guard's population is right and a `mkdtemp` join
genuinely is indistinguishable from a live read by pattern alone.

# What NOT to do

`ALLOWED` is at 33 entries against a comment claiming it is short and argued.
The instinct to trim it is wrong while the guard still works this way: every
entry documents a real fixture, and the entries are the only place the
fixture-vs-live reasoning is written down. **Fix the enforcement point first;
the table's length is a symptom.**

# Provenance

Found by frank-seven on seven at `2d3e5fb9dfd6`, reproducing a `tools-devtest`
red this seat had wrongly concluded was stale or host-specific after all four
NAMED scripts passed on plexus. The third `ALLOWED` entry (`fc2ce3d02`) landed
2026-09-09 with a pointer to this ticket.
