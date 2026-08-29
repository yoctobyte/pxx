---
track: T
prio: 45
type: bug
blocked-by: []
summary: "A test job takes its name from its FIRST source file, but the red is usually a later step -- so the auto-filed regression stub's `track:` guess is derived from a filename that has nothing to do with the failure. Wrong three times on one job: crtl-reachability -1 (red was crtl-map), -3, and -4 (red was lib/pcl's GTK3 guard, Track B). The stub says `track GUESSED from the test path` but the path is not evidence about the defect at all."
status: new
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
