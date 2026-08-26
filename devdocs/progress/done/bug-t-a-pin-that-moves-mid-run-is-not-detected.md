---
track: T
prio: 55
type: bug
blocked-by: []
summary: "testmgr snapshots the HEAD-built compiler and reports `compiler_changed_mid_run`, but the PIN — which lib-test and demos actually build with — is read ONCE at startup and never re-checked. A `make pin` during a run silently splits those jobs across two stables while the report claims a single `pin=N`. The asymmetry is the tell: one binary is guarded, the other is announced."
status: done
owner: pxx-aa
---

# A pin that moves mid-run is not detected

Found 2026-08-25 by Track T while a `full` tier was running and the coordinator
was preparing a pin on `dev`.

## The asymmetry

testmgr already takes provenance seriously for the compiler it builds from HEAD:
it snapshots the binary, records `compiler_sha256`, compares it at the end, and
publishes `INVALID` when it moved — because a run whose PASS/FAIL cannot be
attributed to one binary is not evidence.

`report_pin_identity()` does none of that for the pin. It reads
`stable_linux_amd64/default/VERSION` and `last.sha256` once, prints
`pin=374 sha256=…  (lib-test and demos build with THIS, not HEAD)`, and never
looks again. But `PIN_BUILT_TARGETS = ("lib-test", "demos")` build with
`$(PXX_STABLE)`, which is a symlink the pin moves. So a `make pin` landing
mid-run means some pin-built jobs used v374 and the rest used v375, while the
report states one version for all of them.

## Why it matters here rather than in theory

A full tier at 6 cores runs ~40-67 minutes, and pins happen on `dev` one or
twice a day, held by whoever is coordinating. Those windows overlap. The failure
is quiet in the worst way: `lib-test` reds are exactly the class whose diagnosis
is *"was it a lib change, or is the pin stale relative to what lib/ expects?"* —
the question `report_pin_identity()` exists to answer in a glance — and the
report would answer it with a version half the jobs did not use.

## What to change

The cheap, honest version is symmetry with what already exists for the compiler:

1. Re-read the pin identity at the END of the run. If it moved, set
   `pin_changed_mid_run: true` and name both versions.
2. Do NOT invalidate the whole run. Unlike the compiler snapshot, this affects
   only the two pin-built targets — invalidating 3057 jobs because `lib-test`
   straddled a pin would trade a small wrong claim for a large lost one. Mark
   the pin-built jobs' results as unattributable (they already carry
   `pin_built`, so the set is known) and leave the rest standing.
3. `twatch` should decline to open a regression on a `pin_built` job from a run
   that straddled a pin, for the same reason it declines on `INVALID`.

A snapshot (copying the pinned binary the way the compiler is snapshotted) would
be stronger and is the obvious next thought — but it is 27MB per run and the
pin's whole purpose is to be the one binary every lane shares, so detection is
the right level here. Say what happened; do not try to prevent it.

## Not a hypothetical, but not yet observed in a report

No run in `runs-plexus.ndjson` is known to have straddled a pin — the field to
detect it does not exist, which is the point. Do not write a repro into the
ticket by pinning during a live run just to prove it; the code path is plain
enough to read.

## Measured: which tiers can actually straddle (2026-08-26)

`PIN_BUILT_TARGETS` is a coarse target list and was misleading me; the
authoritative per-job signal is `Job.pin_built` (`PINNED_INVOKE_RE` over the
recipe body). Counted directly off `generate(tier)`:

| tier | jobs | pin_built |
| --- | --- | --- |
| quick | 26 | 0 |
| native | 1554 | 0 |
| limited | 2323 | 0 |
| full | 3057 | 191 (all `lib-test`) |

So the exposure is **confined to the full tier's 191 `lib-test` jobs**. A pin
taken while a quick/native/limited run is in flight cannot corrupt that run's
verdict — nothing in those tiers builds against `stable_*/…/pinned`. That makes
"pin during a native gap" a real, safe window rather than a guess, and it
narrows this ticket's fix: the unattributable set is never more than 191 jobs.

**Adjacent gap, worth folding into the same fix:** the `demos` job reports
`pin_built=0` even though `make demos` builds against the pin — the regex sees
the job's own recipe (`make demos`), and the pinned path only appears inside the
Makefile target it shells out to. Harmless today because `demos` is `advisory`
(reported and ticketed, never gates the verdict), but the flag is wrong and the
next non-advisory shell-out job would inherit the same blind spot. Either mark
`PIN_BUILT_TARGETS` members `pin_built` by name regardless of recipe text, or
resolve one level into the Makefile.

## Resolved 2026-08-26 (pxx-aa, Track T)

All three asks, as written.

1. **The pin is read twice** — `pin_identity()` at the start (alongside the
   existing banner) and again at the end. A move sets `pin_changed_mid_run` and
   both versions are named in the run's output and JSON.
2. **It does NOT invalidate the run.** The compiler snapshot invalidates
   everything because every job used it; the pin is used by 191 of the full
   tier's 3057. The pin-built jobs are listed in `pin_straddled` and everything
   else stands.
3. **twatch declines to open a ledger entry or file a ticket** for a straddled
   pin-built job — and withholds **FIXED** as well as NEW-RED. Same
   unattributable result, and the direction nobody checks: a spurious NEW-RED
   sends someone looking, a spurious FIXED sends nobody. Their statuses still
   land in `st["jobs"]`, so the next complete run diffs against a real picture
   rather than a hole.

The `demos` half of the adjacent gap was fixed earlier the same day (`af29523f1`).

### Two things that would have made this a silent no-op

**`pin_straddled` names jobs by SELECTOR, not by `j.name`.** twatch keys by
`job_key()` — the stable `lib-test#src:<file>` form — while `lib-test#42` is a
positional index into the target's recipe lines that renumbers when a line is
inserted. A list of names is a list twatch matches nothing against: a guard
that runs and never fires. Caught by reading `job_key`'s own docstring, which
warns about exactly this and had been written for a different bug.

**The start-of-run test was `j.target in PIN_BUILT_TARGETS`, the coarse list.**
Now `j.pin_built`, the per-job fact — otherwise a pin-built job outside the
named targets goes unannounced and unguarded, which `test-fpjson` was until
this morning.

### Verified

Per the ticket's instruction not to force a real straddle, the comparison is
proven functionally rather than by pinning during a live run: `pin_identity()`
driven over a stubbed `pin_file` distinguishes v374 from v375 and compares
equal across two reads of an unmoved pin. Report wiring confirmed on a real
`--tier quick` run (`pin: null`, `pin_changed_mid_run: false`,
`pin_straddled: []` — correct, quick has no pin-built jobs).

`tools/testmgr_pin_straddle_devtest.py`, 6 cases.

One of those guards went red on its first run against the **comment** that
explains the rule it checks ("Deliberately NOT `invalid=True`"). It strips
comment lines now. A text-shaped guard reads prose as eagerly as code.

## Log
- 2026-08-26 — resolved, commit PENDING-COMMIT.
