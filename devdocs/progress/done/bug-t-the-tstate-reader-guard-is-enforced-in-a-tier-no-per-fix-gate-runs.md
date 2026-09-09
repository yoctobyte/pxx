---
slug: bug-t-the-tstate-reader-guard-is-enforced-in-a-tier-no-per-fix-gate-runs
track: T
prio: 45
type: bug
status: done
owner: "frankB"
created: 2026-09-09
found-by: frank-seven
tags: [tools, devtest, guard, gate, tstate]
blocked-by: []
summary: "FIXED 2026-09-09, all three candidate fixes. tstate_reader_devtest.py now runs in gate.sh quick (0.41s, min of 3), so the author sees it before landing instead of a full tier hours later at their sha. The tools-devtest recipe captures failures and REPEATS them after the loop, so the log tail names the failing script rather than the ~90 that ran after it alphabetically -- same change applied to tools-devtest-sh. And the guard prints the ALLOWED stanza to paste, separating the live-read case from the synthetic-fixture case it cannot tell apart itself. IT THEN CAUGHT A FOURTH INSTANCE DURING THIS CHANGE'S OWN VERIFICATION SWEEP -- testmgr_red_is_self_describing_devtest.py, written an hour earlier for the sibling ticket, same synthetic-fixture shape as the other three; four for four, still zero tools reading live tstate. Correction: the reason names the LAST four scripts, not the first, because job_reason takes the tail."
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

## 2026-09-09 (frankB) — all three candidate fixes landed; the enforcement point was the ticket

**2 (the ticket's own subject): `tstate_reader_devtest.py` now runs in
`gate.sh quick`.** 0.41s, min of 3 on this box, against a ~30s gate that is
defended. The author sees it before landing, which is the entire complaint. The
`MISSING` arm follows the house pattern beside it — a gate arm that skips on a
tracked file passes green for a tree with no checker in it.

**1: the reason no longer reports the loop's progress.** The failing script's
name and output are captured as they happen and **repeated after the loop**,
where the tail will carry them. The pre-run `printf` stays: this target is ONE
recipe line, so testmgr's `.step` marker cannot narrow a timeout further, and
the last progress line is the only thing that names the script it hung in.

Measured, old recipe against new, same fixture (one failing script early in the
alphabet, three passing after it) — the last four lines, which is what
`job_reason()`'s tail takes:

```
OLD:  tools-devtest: tools/mmm_late_devtest.py
      tools-devtest: tools/nnn_late_devtest.py
      tools-devtest: tools/zzz_late_devtest.py
      tools-devtest: 3 green, 1 RED -- tools/aaa_early_devtest.py

NEW:  ---- the 1 failing script(s), repeated so the log TAIL names them
      FAIL: tools/aaa_early_devtest.py
      FAILED 4 check(s): the assertion this file exists for
      tools-devtest: 3 green, 1 RED -- tools/aaa_early_devtest.py
```

**One correction to this ticket.** It says the reason *"always names the same
first four scripts"*. It names the **last** four — `job_reason()` takes the log
TAIL, and the four it reported (`twatch_toolchain`, `twatch_verify_request`,
`verify_assertions`, `whoholds`) are the alphabetical END of the sweep, run
AFTER the failure the loop did not stop for. The summary line naming the real
failure **was** in the tail and was cut by `REASON_MAX = 400` after five long
progress lines preceding it in log order. Same misdirection, different
mechanism — and the difference is what the fix had to key on.

Applied to `tools-devtest-sh` as well, which had the identical shape. Fixing one
arm of a double case and leaving the sibling is how the second path stays broken.

**3: the guard is self-describing at the point of failure.** The message now
separates the two cases — reads the LIVE archive (route through
`materialize_tstate()`) vs builds a SYNTHETIC fixture under its own tmp dir (the
legitimate pattern, and what all three offenders were) — and prints the
`ALLOWED` stanza to paste. It does **not** decide which case applies; the guard
cannot tell, which is the whole reason the author has to. Verified by adding a
temporary offender and reading the message, then removing it.

`ALLOWED` is left at its current length. This ticket is right that trimming it
is the wrong instinct while every entry is the only place a fixture's
reasoning is written down.

## 2026-09-09 (frankB) — A FOURTH INSTANCE, PRODUCED WHILE FIXING THE THIRD

The guard fired on `testmgr_red_is_self_describing_devtest.py` — the file
written an hour earlier for the sibling ticket — during the verification sweep
for this very change. Instance four, same shape as the other three: a
**synthetic fixture** under its own `mkdtemp`, globbed back with
`os.path.join(tmp, tw.TSTATE_REL, ...)`, never touching the live archive. Four
for four, still zero tools actually reading live tstate.

**Three things it demonstrates that the ticket could only argue.**

1. **The pattern is not carelessness.** That file globs a synthetic report back
   *because* its subject is a rendering defect — a 0-byte job log publishing a
   silent empty ``` block — and grepping the renderer's constants instead would
   pass on a branch that exists and is unreachable. The legitimate reason to
   trip this guard is the same reason the guard cannot tell.

2. **Fix 3 worked as specified.** The failure message printed the ALLOWED
   stanza; it was pasted verbatim and the entry is the one now in the table. No
   reading of this file's history was needed to learn that a fixture is
   legitimate.

3. **Fix 2 changed WHO pays.** The previous three instances were found by the
   full tier hours later, attributed to the author's sha, and cost a seat a pass
   each. This one was found by the author, before pushing, in the sweep they
   were already running — and with the guard now in `gate.sh quick` it would
   have surfaced ~30s after the file was written.

**And the recipe change is visible in the same log.** The failing script is
named in the last four lines rather than buried under the ~90 scripts that ran
after it alphabetically, which is the misdirection this ticket was filed for.

**One process note, because it is the reason this was seen at all.** The first
verification sweep was killed and restarted: I had edited `tools/testmgr.py`
after starting it. The edit was comment-only and almost certainly harmless — and
the restarted run is the one that reached this red, because the first had not
yet got past `p` alphabetically. *"Do not touch the instrument while it is
measuring"* paid here for a reason unrelated to the corruption it guards against.

## Log
- 2026-09-09 — resolved; this names the commit that carried the resolve, which is not always the one that carried the change — commit PENDING-COMMIT.
