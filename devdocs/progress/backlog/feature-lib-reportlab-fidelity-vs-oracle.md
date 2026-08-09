---
blocked-by: decide-may-agents-fetch-thirdparty-sources-as-oracles
summary: "The reportlab mimic produces a VALID PDF, never one shown to agree with real reportlab. Differential-test lib/pcl/mimic_reportlab_* against CPython+reportlab on the same script"
type: feature
track: B
prio: 45
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

## Blocked 2026-08-09 (Track B): the oracle is not on this box

This ticket is a DIFFERENTIAL one — its whole content is "compare against real
reportlab" — and neither `reportlab` nor `pdfplumber` is installed here
(`pdftotext` is). Writing the harness without the oracle would produce a harness
that has never once been run against the thing it exists to compare with.

Blocked on [[decide-may-agents-fetch-thirdparty-sources-as-oracles]], the same
wall [[feature-nilpy-codecs-shim]] hit. Once an oracle is available the ticket
is ready to go as written — the shape, the comparison level (extracted text plus
per-glyph positions rather than PDF bytes) and the starting cases are all
already decided here.

