---
summary: "CORPUS_RE captures punctuation out of recipe PROSE and invents a corpus tree that cannot exist, silently skipping the job — twice: 'stb)' 2026-07-31, and 'zlib.' 2026-09-06 after the first fix removed ')' and kept '.'"
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


---

## REOPENED 2026-09-06 — the same defect, one character narrower

The 2026-07-31 fix tightened the class to `[A-Za-z0-9_.+-]+`, which removed `)`
and **kept `.`**. A sentence-ending full stop after a corpus path is therefore
still swallowed. `test-zlib`'s recipe carries a shell-comment line

```
	: '  other zlib header still resolves out of $(ZLIB_SRC).'; \
```

which `make -n` hands the detector as `... out of library_candidates/zlib.`.
The capture is `zlib.`, `library_candidates/zlib.` is not a directory, and the
job self-skips on every host as `corpus absent: library_candidates/zlib.`
— fetched or not.

### It cost seventeen minutes of coverage on the release box, not eight days

Measured from seven's own reports in `devdocs/progress/tstate/reports/`:

| when | sha | tier | skips / holes | test-zlib |
| --- | --- | --- | --- | --- |
| 18:02:17Z | `c69b52b` | full | 6 / 1 | RAN (present as a red job) |
| 18:20:46Z | `2523453c4` | — | — | the comment line lands |
| 18:37:24Z | `6d04b14` | full | 7 / 2 | SKIPPED, "corpus absent" |

`2523453c4` is *"fix(T): test-zlib's unity runner was invalid C — the compiler
was right"* — a commit whose entire purpose was to make this row measurable.
**The fix hid the row it fixed**, and the very next tier recorded the skip. The
corpus itself had been present on that box since 2026-08-29 and never moved, so
every reading that starts from "the corpus is missing" is chasing a fact that
was never true.

### Why the devtest could not catch it — two independent reasons

`tools/testmgr_corpus_skip_devtest.py`'s `case_real_makefile_yields_only_real_trees`
was written for exactly this and passed throughout.

1. **Wrong population.** It scans the Makefile SOURCE, where the line still
   reads `$(ZLIB_SRC).`; the string `library_candidates/zlib.` exists only in
   `make -n` OUTPUT, which is what the detector actually reads. A control drawn
   from the wrong population passes and certifies the broken instrument.
2. **Wrong alphabet.** Its phantom filter tests for `()[]{};"'` `` ` `` `$`. A
   full stop is in none of them — it could not have failed on this shape even
   with the right input.

### The fix

`CORPUS_RE` may no longer capture a name ENDING in a dot. An interior dot is
left alone: no corpus has one today, and forbidding it would be the opposite
defect the day someone fetches `lua5.4`. Repaired at the INSTRUMENT rather than
at the comment, because the comment is one writer away from coming back and the
next prose sentence to end in a corpus path lands somewhere with no repro.

Three devtest cases added, labelled by what each can actually observe: the
trailing-dot case is the regression control and was verified to FAIL under the
pre-fix regex; the interior-dot case passes under the pre-fix regex too and its
docstring says so, so nobody counts it as a control it cannot be.

### The residual, NOT fixed here, and it has no owner yet

A recipe's own SKIP line can never be counted as a skip HOLE. `_self_skipped`
returns the whole matched line, which always begins `<target>: SKIP`, while
`SKIP_HOLE_PREFIXES` matches at position 0. So every self-skipping recipe arm —
`test-zlib`'s own `gcc oracle not found`, and the five gtk skips on the
18:37:24Z report — is counted in `skips` and never in `skip_holes`. Five of
seven skips there were invisible to the coverage number. Flagged to frankB, who
holds the neighbouring absence-detector defect; it is a design question about
hole accounting, not a typo.
