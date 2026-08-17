---
summary: "The reportlab mimic produces a VALID PDF, never one shown to agree with real reportlab. Differential-test lib/pcl/mimic_reportlab_* against CPython+reportlab on the same script"
type: feature
track: B
prio: 45
status: done
owner: frank3
---

# reportlab mimic: fidelity against the real oracle

- **Type:** feature (differential testing). Track B.
- **Opened:** 2026-08-06, re-filed from
  [[feature-lib-pxxpdf-reportlab-compat]] per
  [[decide-pxxpdf-ticket-obsolete]] — everything else in that ticket shipped.

## The gap

The mimic's acceptance was *"output matching the reportlab output"*. What was
demonstrated is that a reportlab-using nilpy program compiles, runs, and writes
a `%PDF-1.3` whose text `pdftotext` extracts.

**Validity is not agreement.** A PDF can be structurally valid and still place
text at the wrong baseline, pick a different font metric, or lay out a wrapped
paragraph differently. Nothing has compared our bytes, or our rendering, to
what real reportlab produces from the same script.

## Shape

Same pattern as the other differential probes
(`devdocs/dev/differential-probes.md`): one script, two implementations, compare.

- **oracle:** CPython + reportlab, on a machine that has it;
- **candidate:** the same unmodified `.py` compiled with pxx against
  `lib/pcl/mimic_reportlab_*.pas`;
- **compare at the level that is meaningful.** Byte-identical PDFs are the
  wrong bar — both embed timestamps and object ordering is not canonical.
  Compare extracted text plus per-glyph positions (`pdftotext -bbox`, or
  `pdfplumber`), which is what "matching" means for a drawing API.

Start with the cases the parallel-canvas work already exercised, since the
screen-vs-PDF fidelity fixes there (baseline anchor, PIXEL font sizes, per-word
placement) are exactly the class of divergence this would catch.

## Why it is worth doing rather than assuming

The mimic implements a drawing API by reimplementation, not by wrapping — every
metric, default and coordinate convention is an independent guess that happens
to look right. Those are silent-divergence conditions, and this repo's
experience is that plausible-looking output is where the expensive bugs live.

## Gate

A differential harness exists and runs; a documented set of scripts agrees with
the reportlab oracle on extracted text and glyph positions within a stated
tolerance; divergences are either fixed or ticketed with the measurement.

## UNBLOCKED 2026-08-09 — the policy question was answered

The user's call: a library named in project documentation may be fetched, via
`tools/install_lib_candidates.sh`. reportlab is named right here, so it clears
the bar. What remains is adding it as a pinned candidate (the tool's list is
otherwise all C) and then doing the differential work as written.

The original block, for the record:

## Was blocked 2026-08-09 (Track B): the oracle is not on this box

This ticket is a DIFFERENTIAL one — its whole content is "compare against real
reportlab" — and neither `reportlab` nor `pdfplumber` is installed here
(`pdftotext` is). Writing the harness without the oracle would produce a harness
that has never once been run against the thing it exists to compare with.

Blocked on [[decide-may-agents-fetch-thirdparty-sources-as-oracles]], the same
wall [[feature-nilpy-codecs-shim]] hit. Once an oracle is available the ticket
is ready to go as written — the shape, the comparison level (extracted text plus
per-glyph positions rather than PDF bytes) and the starting cases are all
already decided here.

## 2026-08-09 (Track B): harness built, oracle pinned, three real bugs found

**The harness exists and runs:** `tools/reportlab_diff.py`. reportlab 4.2.5 is
pinned in `tools/install_lib_candidates.sh` (sdist + SHA256 — upstream is
Mercurial and the GitHub mirror's tags are 2002-era artefacts, so PyPI is the
pinnable source). It runs ONE script through both implementations and compares
extracted text plus per-word bounding boxes from `pdftotext -bbox` — the level
this ticket specified, since byte-identical PDFs are the wrong bar.

**It found what the ticket predicted it would.** "Validity is not agreement" was
right three times over:

1. **`canvas.Canvas("out.pdf")` SEGFAULTED** — the one-argument form, which is
   reportlab's most common and the first line of nearly every example. The
   mimic's `pagesize` parameter had no default where reportlab's does, so the
   ctor read an uninitialised Variant. Fixed (`= 0`; the body already fell back
   to A4). *Nothing in-tree caught this because the only reportlab test exercises
   IMPORTS, never a Canvas.*

2. **A 0.11pt systematic baseline shift.** Every word was 0.1102pt low — across
   four fonts and four sizes, with x positions and word widths already EXACT.
   That constant is `842.0 - 841.8897637795`: the ctor hardcoded A4 as
   `595.0 x 842.0` while `mimic_reportlab_lib_pagesizes` already had the exact
   210x297mm conversion. Two places encoding "A4", disagreeing. Fixed to the
   exact values; positions now match reportlab to **0.000029 pt**, which is
   `pdftotext`'s own print precision, and widths to **0.000000**.

3. **`AnsiString` handed raw to `const char *`** in five places including
   `drawString`'s text — the most-used call in the shim. All now go through
   `PChar()`.

**Still open:** [[bug-b-reportlab-mimic-multi-font-heap-corruption]] — four or
more distinct fonts corrupts the heap intermittently (~1 run in 6; 3 in 10 under
`-dPXX_HEAP_DEBUG`). Filed at prio 55 with the full diagnosis, including that
the vendored writer and the C frontend are both exonerated: driving
`lib/vendor/pdfgen` directly with four fonts works under gcc AND pxx.

The harness is deliberately **NOT wired into `make lib-test`** while that bug is
live — it would make the gate intermittently red on a known issue. Wire it in
when the crash is fixed; until then it is a probe you run
(`tools/reportlab_diff.py`), like the other differential probes.

**Where it stands per case:** `positions` (1 font, 4 strings) matches reportlab
exactly. `text_fonts` and `many_fonts` cannot complete until the heap bug is
fixed.

## 2026-08-09 (Track B): harness re-run — and it re-diagnosed the blocker

Re-ran all three cases. `text_fonts` matches reportlab at **worst delta 0.000029
pt** (pdftotext's own print precision), confirming the fidelity work holds. The
other two are gated purely by the crash, not by any measured divergence.

The re-run also corrected the crash's diagnosis — see
[[bug-b-reportlab-mimic-multi-font-heap-corruption]]. It is a **stack** overrun
triggered by `showPage()`, reproducible in three lines with no fonts or text,
and is neither multi-font nor heap-related as previously recorded. Which case
"passes" on any given run is just the crash rate, so the earlier per-case notes
(`positions` matches / `text_fonts` cannot complete) were sampling noise and
should not be read as fidelity results.

Still deliberately NOT wired into `make lib-test` while the crash is live.

### Blocker is Track N's, not Track B's

The crash gating `positions` and `many_fonts` was isolated to the NilPy path —
the identical calls from Pascal are 25/25 clean — and re-filed as `track: N`.
Nothing further is actionable here under Track B until that lands; the harness
and the shim are both ready, and the one case that completes agrees with the
oracle to 0.000029 pt.

## 2026-08-17 — WIRED INTO THE GATE (Track B, frank3)

The ticket's last note said "nothing further is actionable here under Track B
until [the NilPy crash] lands". That was 8 days old, so it was **measured rather
than trusted** — and it no longer holds.

### The blocker is gone, and one green run does not say so

Fetched the oracle (`tools/install_lib_candidates.sh reportlab`) and ran the
harness. All three cases pass:

```
many_fonts   ok (5 words, worst delta 0.000029 pt)
positions    ok (4 words, worst delta 0.000029 pt)
text_fonts   ok (9 words, worst delta 0.000029 pt)
REPORTLAB DIFF: OK
```

The crash this was parked on was **intermittent** (~1 run in 6), and this
ticket's own history records the trap: earlier per-case results here were
sampling noise read as fidelity findings. So a single green run is worth
nothing as evidence that it is fixed. **Ran the harness 20 times: 20/20 clean,
0 failures.** That is the measurement that justifies wiring it into a gate; the
0.000029 pt figure was never the question, the crash rate was.

0.000029 pt is `pdftotext`'s own print precision, against a tolerance of 1e-3 pt
(~350 nm on paper) — so the mimic and real reportlab agree on glyph placement as
closely as the extraction tool can report.

### Wired in

`make lib-test` now runs `tools/reportlab_diff.py`, which the ticket
deliberately deferred while the crash was live. ~16.5 s.

```make
@rc=0; tools/reportlab_diff.py || rc=$$?; \
 if [ $$rc = 77 ]; then echo "SKIP reportlab_diff -- prerequisite absent (see line above)"; \
 elif [ $$rc != 0 ]; then echo "reportlab_diff: the mimic diverged from the oracle"; exit 1; fi
```

Exit 77 means a prerequisite is absent and **nothing was compared** — skip
loudly, the same shape as the synapse guard added earlier today
([[bug-b-lib-test-unrunnable-in-a-fresh-clone-no-synapse-fetch]]), so a fresh
clone cannot read a missing vendor tree as a divergence.

### A second 77 case the wiring exposed

The harness returned 77 for a missing oracle but **not** for a missing
`pdftotext`: that path fell through to a bare `subprocess.run`, raising an
uncaught `FileNotFoundError` and exiting 1. Confirmed as the real failure mode,
not assumed. Harmless while this was a probe you ran by hand; the moment it
became a gate it meant **a box without poppler-utils would report "the mimic
diverged from reportlab" when nothing had been compared at all** — which is the
precise confusion the third exit code exists to prevent. Now `shutil.which`
returns 77 with its own message.

### Gate — both branches exercised in the real target, not simulated

| state | `make lib-test` |
| --- | --- |
| oracle + pdftotext present | **exit 0**, `REPORTLAB DIFF: OK`, three cases at 0.000029 pt |
| `library_candidates/reportlab` moved away | **exit 0**, prints the oracle-absent line + `SKIP reportlab_diff` |
| PATH without `pdftotext` (harness direct) | exit 77, `pdftotext absent (poppler-utils)` |

### What this ticket asked for, and where it stands

The gate line asked for a harness that runs, a documented set of scripts
agreeing with the oracle within a stated tolerance, and divergences fixed or
ticketed. All three hold: the harness is in `make lib-test` rather than
optional, the three cases agree to 0.000029 pt against a 1e-3 pt tolerance, and
the three divergences it originally found (the one-arg `Canvas` segfault, the
0.11 pt A4 baseline shift from two disagreeing encodings of A4, and five raw
`AnsiString`→`const char *` sites) were fixed on 2026-08-09.

**Coverage is deliberately not what this measures.** The cases stay inside the
mimic's documented subset because this probe tests fidelity — a case using
something the mimic refuses would fail loudly and teach nothing. Widening the
subset is separate work and wants its own ticket.

Resolving. [[bug-b-reportlab-mimic-multi-font-heap-corruption]] remains open and
owned by agent-AN; the 20/20 run data is added there as evidence but its
diagnosis and status are untouched — a rarer residual is exactly the thing 20
runs cannot rule out.

## Log
- 2026-08-17 — resolved, commit 261184893.
