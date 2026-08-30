---
track: T
prio: 45
type: bug
blocked-by: []
summary: "A test job takes its name from its FIRST source file, but the red is usually a later step -- so the auto-filed regression stub's `track:` guess is derived from a filename that has nothing to do with the failure. Wrong three times on one job: crtl-reachability -1 (red was crtl-map), -3, and -4 (red was lib/pcl's GTK3 guard, Track B). The stub says `track GUESSED from the test path` but the path is not evidence about the defect at all."
status: done
owner: ""
---

# A job named after its first source file cannot name its failing step

- **Type:** bug (Track T — testmgr / the auto-filed regression stub).
- **Found:** 2026-08-29 by frankC, third occurrence on one job; filed by the
  coordinator at frankC's triage.

## The measurement

`regression-lib-test-crtl-reachability-4` was filed `track: C`. The C-frontend
lane chased it. **`crtl-reachability` passes.** The red was a later step in the
same job — `lib/pcl`'s own `{$ERROR}` firing because `<gtk/gtk.h>` resolved to
GTK2, which is **Track B**, retracked at `fd1c9b280`.

This is the third time on the same job:

| ticket | `track:` guessed | step that was actually red | real lane |
| --- | --- | --- | --- |
| `...crtl-reachability-1` | C | `crtl-map` | — |
| `...crtl-reachability-3` | C | a later step | B |
| `...crtl-reachability-4` | C | `lib-units`, `lib/pcl` GTK3 guard | **B** |

## The mechanism, which is not the truncation

A job is **named after its first source file**. The red is usually a *later*
step. So the name and the failure are related only by which file happened to be
first in the job's list, and the `track:` heuristic reads **the name**.

The stub already carries `[track GUESSED from the test path — the defect may be
in another lane; verify before claiming]`, which is honest about *confidence*
and wrong about *kind*: it implies the path is weak evidence about the defect.
**It is not weak evidence, it is not evidence** — it identifies the job, and the
job spans several lanes' files by construction. A reader who "verifies before
claiming" is still being pointed at the wrong lane first, which is what happened
three times.

## Why this is worth fixing rather than documenting

Each occurrence cost a lane a triage it should never have received, and the
third one cost the C lane an evening's queue slot while its own blocker sat
unranked. **A documented trap is not a guard** — the warning string has been
present for all three.

## Two candidate fixes, both cheap

1. **Name the failing STEP, not the job's first file.** The step is known at
   report time; the stub could be
   `regression-lib-units-pcl-gtk3` rather than
   `regression-lib-test-crtl-reachability-4`. This fixes the slug, the `track:`
   guess and the human-readability in one change.
2. **Derive `track:` from the failing step's file, or refuse to guess.** If the
   step's own source file is known, that path is real evidence. If it is not,
   emitting no `track:` is better than emitting a wrong one — an absent field
   gets triaged, a wrong field gets believed. Same asymmetry as *a false limit
   is quieter than a false fix*.

Prefer (1); it subsumes (2) and removes the misleading slug as well.

## Related, already fixed

`tools/lib_units_compile.py` printed `splitlines()[:3]` of each failure, and
every GTK unit emits three host-header **warnings** before its error — so the
one line naming the owning lane never reached the ticket, the tstate report, or
anywhere else. Fixed at `151adfbeb` (rank error-bearing lines first, print a
dropped-count instead of truncating silently). **That was a contributing cause
of the mis-tracking but not the root one**: even with the error line present,
the slug and the `track:` guess still come from the job's first source file.

---

## Resolved 2026-08-30 — the step is read, not inferred; the slug does not move

**Proposal (1) is refuted, and the refutation is structural rather than a
preference.** The ticket asked for the SLUG to be built from the failing step.
It cannot be, for two reasons the code makes checkable:

1. **The slug is the dedupe key AND the close key, and the two are computed at
   different times from different data.** `stub_slug_for_filing()` derives it
   from the job when FILING. `close_stub_tickets()` recomputes it as
   `reg_slug(r["job"])` when CLOSING — where no step is in scope, because the
   closing run is the one where the job went *green*. A step-derived slug is
   therefore unfindable at close time, so every stub would leak open, silently.
   That is the exact failure `feature-t-autoticket-must-close-its-own-stubs-when-fixed`
   existed to end.
2. **`progress.py` derives a ticket's `type` from the slug's first token**
   (`Ticket.type = slug.split("-", 1)[0]`). `regression-lib-units-pcl-gtk3`
   would become a ticket of type `lib`.

And a step-derived slug is not stable ACROSS RUNS: one broken job failing at a
different line tomorrow files a second ticket for one defect — which is what
the stable-selector slug was introduced to stop.

So the step lands in the three places that ARE free to move, and the slug stays
put.

### What was built

**`tools/testmgr.py` — the step is measured, not guessed.** `Job.script()`
writes the recipe-line index to a marker file *before* each line, so a red
names the line that failed and a TIMEOUT names the line it was sitting in. A
marker FILE and not a marker printed into the log: the log is what
`job_reason()` and `diagnostic_lines()` read, and salting it would put harness
output in front of the error two previous tickets were spent surfacing.
`report_job()` gains `step_i` / `step_n` / `step_line` / `step_src`, always
present and filled only for a red — the same contract `subject` has.

**`tools/twatch.py` — routing, the H1, and a body bullet.**

- `track:` is guessed from the FAILING STEP's own sources. When the step names
  a lane, the job's `src` is not consulted at all: falling back to it is the
  defect, not a safety net.
- **Bounded**, and the bound matters more than the rule. A job that names ONE
  source has no first-source problem — first and only are the same file, no
  other lane is in frame — so a single-source job whose failing step names
  nothing of its own (`compile foo.pas`, then `diff foo.expected -`) keeps its
  source's track. Without that bound the entire single-test majority would have
  been swept to T, which is a bigger mis-routing than the one being fixed.
- A MULTI-source job whose failing step names no lane **refuses to guess** and
  says so, naming the step and stating that the job's `src` was deliberately
  not used. That is proposal (2), applied exactly where it is evidence.
- The **H1** carries the step. This is not cosmetic: a stub has no `summary:`
  frontmatter, so `progress.py` falls back to the first `# ` heading — the H1
  *is* the line `ready`/`next` print and the line a dispatcher routes on.
- A job whose first run is red is headed **`first-ever red`**, not
  `regression`. `range_note()` has said so in the body for a while, three
  sections down, where a board reader never reaches. The slug still begins
  `regression-` and must (see above); the heading is where the correction can
  live, and the disagreement between them is the honest state of affairs.

### Measured, against the ticket's own case and against one it did not choose

`lib-test#00` is **198 recipe lines naming 39 source files** across Tracks A,
B, C and T. That is the whole finding in one number: `src` is the first two of
thirty-nine.

| step | line | old `track:` | new `track:` |
| --- | --- | --- | --- |
| 17 | `python3 tools/crtl_reachability.py` | C | C |
| 22 | `python3 tools/gen_crtl_map.py --check` | C | C |
| **28** | `python3 tools/lib_units_compile.py` | **C** | **B** |

Step 28 is `crtl-reachability-4`, the occurrence in the table above whose real
lane was B and which cost the C lane an evening. Steps 17 and 22 are unchanged,
correctly: those reds really were in crtl's own files.

**It does NOT fix the case the coordinator handed over, and that is worth
stating rather than absorbing.** `test-threads#src:test/test_cmp_both_in_place.pas@2`
fails in step 3 of 14, whose text names `test/test_cmp_both_in_place.pas` — so
the step-derived track is P, the same wrong answer as before. The owner
(`frank-optimize-b4`, whose commit `d1535b899` the test belongs to) is not
derivable from any path, and no rule over filenames will find it. What the step
DOES deliver there is the arm: the failing line reads
`... for o in 0 3; do ./compiler/pascal26 --target=aarch64 ...`, so **aarch64**
is now in the H1 and the body instead of being reconstructed by hand from the
log tail. Of the coordinator's four facts, the step names the arm, the H1 names
the novelty, and the routing fixes the ticket's own case; **ownership remains
unrecoverable** and is the honest residue.

Proof through the real launch path, not a synthetic one: a forced timeout
reports `step_i=0`, `step_line='while :; do :; done'` — with an **empty log
section**, which is exactly when the step field is the only thing that speaks.

**Gate:** `tools/twatch_failing_step_devtest.py`, 14 guards, 5 negative
controls each verified to red only its own guard. Fixedpoint `67f47b5bc540`.

### Three sibling reds this turned up, all fixed here

- `tools/report_exp_dur_devtest.py` asserted the report's key set exactly —
  which is the guard working, and it needed the four new keys documented.
- `tools/testmgr_outgrown_class_devtest.py` asserted *"an untrusted EWMA raises
  nothing"*, which `013948195` deliberately superseded with the one-off
  unproven grant. It had been red in `tools-devtest` since that landing and
  nobody saw it, because that session ran the devtests it expected to be
  affected rather than the population. Updated to assert the grant AND its
  refusal once spent.
- `tools/tstate_reader_devtest.py` — the new devtest's fixture clone needed an
  argued allowlist entry.

Two reds remain that predate this work and are NOT mine to close here:
`tools/exit_observable_devtest.py` (a stdout-only ratchet set at 531 on
2026-08-30, now measuring 548) and `tools/bench_timing_devtest.py` (*"the old
path snaps to ONE poll wakeup"*). Both fail identically at HEAD without this
change.

## Log
- 2026-08-30 — resolved, commit ae26693a3.
