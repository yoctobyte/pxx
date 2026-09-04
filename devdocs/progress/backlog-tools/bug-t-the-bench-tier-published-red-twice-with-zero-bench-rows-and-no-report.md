---
prio: 60
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

---

## 2026-09-04, frankuser (coordinator): it is not twice. It is 33, over seven weeks.

The slug and title say **twice**; that was true when written. Measured on origin
just now:

```
git log origin/master --oneline --grep="bench.*RED (0 bench rows"   ->  33
first: 1f0c52537   2026-07-15 09:27
last:  f879e56b6   2026-09-04 04:40
```

**Every one is identical** — `RED (0 bench rows, 550 conf)`. Same verdict, same
zero, same 550, for seven weeks.

**Not renaming the file**, because the slug is cited and this arc has been bitten
by moving identifiers. But the title now understates by 16x, and the title is the
part everyone reads.

**What this changes about the ticket's own careful scoping.** The body says it
does not claim the tier is broken, only that a RED was published with nothing
behind it. That restraint was right for two runs. At 33 identical runs across
seven weeks, the *verdict* is a constant — and a verdict that never varies cannot
discriminate, which is CLAUDE.md's *a gate that cannot pass is not a gate*. The
bench tier has published the same RED since 07-15 regardless of the tree.

**This is the same shape as `tools-devtest#00`** (`86b174f06`: seven, 308 full
reports, 0 GREEN) and the same neighbourhood as
`bug-t-a-backgrounded-tier-reports-the-wrappers-exit-code-over-the-tiers-verdict`
(`b5d5f977d`, now claimed). **Three instruments, each answering truthfully about
something other than the question its reader is asking.** Prio left at 50 for
Track T to set — the sibling was re-ranked 65 -> 75 on a smaller span.

**Still not established, and this does not establish it:** whether the RED comes
from the zero bench rows or from something among the 550 conformance rows. The
count says the condition is standing; it says nothing about the cause. Recorded
by the coordinator, not measured beyond the count above.

---

## Is this the same path as the backgrounded-wrapper bug? No — same CLASS, different paths (claude-T, 2026-09-04)

Asked before the two get fixed separately. Answered from the code, and the answer
matters because **fixing either will not fix the other.**

Re-ranked 50 → 60 on the count, not on this. Deliberately not 75 like
`tools-devtest#00`: that job decides the `full` verdict, which `pin_is_green`
reads. **This lane is `run_bench_idle` — an idle lane that gates nothing**, so a
constant verdict here costs information, not a gate.

### The bench path

`run_bench_idle` (`tools/twatch.py:5443`):

```python
proc = subprocess.Popen([sys.executable, …])
…
r = proc.returncode
…
clone.publish("tstate(%s): bench %s %s (%d bench rows, %d conf)"
              % (…, "ok" if r == 0 else "RED", rows, conf_rows))
```

The verdict is **one bit off a process exit code**. And `grep` over the whole
function for `write_report` / `reports/` returns **nothing** — the bench lane has
never written a report. So the ticket's title is describing the design, not a
failure: there is no report because this path does not make one.

### Why that is the real defect, and why the cause is unestablished

The original body declines to say the tier is broken, only that a RED was
published with nothing behind it. **That restraint was right and it is also the
whole problem**: nothing survives a bench RED except the word RED and two
counts. There is no output, no log, no report. So "is the RED the zero bench rows
or something among the 550 conformance rows?" is not merely unanswered — it is
**unanswerable from the record**, and will stay so for run 34.

Seven weeks of identical `RED (0 bench rows, 550 conf)` is therefore not seven
weeks of an unnoticed bug. It is seven weeks of an instrument that reports a
verdict and discards the only thing that could explain it.

### The class, and the third instance

Same family as the backgrounded wrapper reporting `exit code 0` over
`testmgr: RED` — both take a verdict from a process's exit status rather than
from the thing that knows the verdict. But **not the same code**: this is
`Popen`+`returncode` inside `run_bench_idle`; the wrapper case is a background
task's notification reporting a shell wrapper's status, outside twatch entirely.
Two fixes, not one.

What they DO share with a third finding is more useful than the class:

| instrument | what it discards |
| --- | --- |
| bench lane | the runner's entire output, on every RED |
| `selfhost_fixedpoint.sh:41` | `stage_2a` and `tested`, via `trap 'rm -rf "$T"' EXIT`, on FAIL |
| backgrounded wrapper | the tier's verdict, in favour of the wrapper's rc |

**Three instruments that destroy the evidence for the verdict they publish.** In
each case the remedy is the same shape and cheaper than the diagnosis: keep the
artifact on failure. For this ticket that is "persist the bench runner's stdout
when `r != 0`", which would make run 34 diagnosable without answering any of the
questions this ticket correctly refuses to guess at.

### Not touched

The cause. Zero bench rows with 550 conformance rows is the same pair in all 33
runs and I did not go looking either — but note the pairing itself is a clue
nobody has used: a run that produced 550 of one kind of row and 0 of another did
not fail early.
