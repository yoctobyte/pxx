---
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

