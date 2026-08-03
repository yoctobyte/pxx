---
summary: "CORPUS_RE matches prose in a SKIP message and invents corpus 'stb)', permanently skipping a job that also carries a non-corpus regression test"
type: bug
track: T
prio: 55
status: done-followup
owner: claude@xeon
---

# `CORPUS_RE` invents a corpus tree that can never exist

- **Type:** bug (Track T — `tools/testmgr.py`)
- **Found:** 2026-07-31, corpus audit while enrolling the xeon watcher box.

## The defect

```py
CORPUS_RE = re.compile(r"library_candidates/([^/\s\"']+)")
```

The character class excludes `/`, whitespace and quotes — but **not `)`**. So it
matches the *prose inside a shell SKIP message* in `Makefile:2426`:

```
else echo "stb_sprintf_probe: SKIP (no library_candidates/stb)"; fi
```

and extracts the corpus name **`stb)`**. `library_candidates/stb)` is never a
directory, so the self-skip check marks the job `skip` **permanently — on every
host, whether or not the corpus is fetched**.

Measured on xeon: after `install_lib_candidates.sh all` fetched all 19 trees,
exactly one job still skipped:

```
!! CORPUS MISSING — 1 job(s) will SKIP, not run.
!!   stb)    1 job(s)
!! Fetch them:  tools/install_lib_candidates.sh stb)
```

The remedy it prints is itself invalid — `install_lib_candidates.sh` dies with
`unknown candidate 'stb)'`.

## Blast radius — worse than one corpus probe

The affected job is `test-core#403`, and it bundles **two** sources:

```
test-core#403   corpus   5 lines   test/cswitch_noncompound_duff_b207.c
                                   test/gamelib/stb_sprintf_probe.c
```

`cswitch_noncompound_duff_b207.c` is the **non-compound switch body + Duff's
device** regression test (`bug-c-switch-nonblock-and-duffs-device`). It has no
corpus dependency whatsoever, and it has not run on any watcher host since the
stb probe was appended to the same target.

## It is invisible in tstate, which is the real problem

`tools/twatch.py:518` records a skipped job as **`"pass"`**:

```py
now = {job_key(j): ("pass" if j["status"] == "skip" else j["status"]) ...}
```

So `borg.json` carries
`test-core#src:test/cswitch_noncompound_duff_b207.c = "pass"` for a job that
never executed. The run-time warning is loud; the **published** state is
silently green. Any cross-host comparison reads it as covered.

## Fix

1. Add `)` (and `;`) to the excluded set, or better, only scan recipe *paths*
   rather than free text — e.g. require the match be followed by `/` or a word
   boundary that is not punctuation:
   `re.compile(r"library_candidates/([A-Za-z0-9_.+-]+)")`.
   Verified against every current reference: the cleaned pattern yields exactly
   the 16 real trees and no phantoms.
2. Split the stb probe out of the b207 job, or teach the chunker not to merge a
   corpus-guarded recipe line with unguarded regression tests — one absent
   corpus should never take an unrelated test down with it.
3. **Give `skip` its own status in tstate** instead of laundering it to `pass`.
   Green must mean "ran and passed". A separate `skip` count per host also makes
   host-to-host coverage differences visible at cutover time, which is exactly
   when they matter.

Item 3 changes the tstate schema, so it wants a deliberate migration rather than
a drive-by — but items 1 and 2 are self-contained.

## Log
- 2026-08-03 — resolved, commit c7400944e.
  Items 1 and 2 only; item 3 (skip published as pass) is split out as
  [[bug-t-tstate-launders-skip-into-pass]] — it changes the tstate schema.
