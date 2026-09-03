---
prio: 50
track: T
---

# bug(T): the bench tier published RED twice with ZERO bench rows and no report

Two consecutive runs on seven, both RED, both with no rows for the measurement
the tier is named after:

```
ad5c990e1  tstate(seven): bench 71a66c7d1437 RED (0 bench rows, 550 conf)
71a66c7d1  tstate(seven): bench 5d083bd91f9a RED (0 bench rows, 550 conf)
```

`twatch.py:5592` formats that line as `(%d bench rows, %d conf)`, so the counts
are bench rows and conformance rows. **Neither commit wrote a report** — each
touched only `tstate/seven.json`, changing `date`, `probe_ratio` and `sha`. So
there is a published RED verdict with **no rows and no detail behind it.**

## What is NOT established here

Whether the RED comes from the zero bench rows or from something among the 550
conformance rows. The subject line carries counts only, and with no report there
is nothing to read. **This ticket does not claim the tier is broken** — it claims
the verdict is unreadable, which is true either way.

## Why it is worth a ticket rather than a shrug

The benign reading is real: bench needs a quiet box, the fleet has been running
several sessions all day, and a bench tier that **refuses to produce numbers on a
loaded machine is behaving correctly.** If that is what happened, the defect is
only that it says `RED` for it.

But that reading is exactly the problem. **A tier that reports RED when it
measured nothing is indistinguishable from a tier that measured and found a
regression** — and this repo has already paid for a verdict that answers a
different question than the one being asked of it. A refusal to measure wants a
word that is not the word for a failure: `SKIP`, or a coverage banner like the
one the native tier already prints for jobs that did not run on the box.

Two runs in a row also means nobody can tell whether this is a new condition or
the steady state, because there is no report to compare.

## Suggested shape

1. Say which of the two produced the RED — bench emptiness or a conformance row.
2. If zero bench rows is a refusal, publish it as a refusal with the reason, not
   as RED; if it is a failure to collect, that is a bug and wants the report.
3. Emit a report on the bench tier even when it has no rows. **A run that
   produces no artefact cannot be diagnosed later**, and both of these are now
   unreconstructable.

## Provenance

Noticed by the coordinator on a fleet-watch pass, from the commit subjects
alone. Not reproduced, not measured — Track T owns the tool and can tell in
seconds whether a loaded box explains it.

## Start here — `tools/twatch_bench_quiet_devtest.py` already exists

Found on the next watch pass (the tier published a THIRD zero-row RED,
`9c39737ea`, so this is the steady state and not a blip). There is already a
devtest named for bench quietness — 10628 bytes, dated 2026-08-27, so it
predates all three of these runs.

**That changes the likely shape of this ticket.** If the quiet-box path is
already modelled and tested, then zero bench rows on a loaded machine is
probably the DESIGNED behaviour and the only defect is that it is published with
the word `RED` and no artefact. Read that devtest before touching `twatch.py`:
it may already say what the intended verdict is, in which case this is a
reporting fix rather than a collection one.

**And if that devtest is green while the tier publishes RED with no rows**, the
devtest is asserting something other than what ships — which is the more
interesting finding of the two and should be filed as its own.

Unrelated but noted from the same report so nobody re-derives it: the full
tier's `STILL-RED tools-devtest#00` is long-standing (reports back to
2026-08-30) and is already covered by
`bug-t-the-exit-observable-ratchet-was-red-at-its-own-arming-commit` and
`bug-t-pin-verify-builds-with-the-previous-pin-not-the-one-it-names`. Not a new
red, not unowned.
