---
slug: bug-t-the-ladder-scan-passes-only-one-root-so-cross-package-imports-read-as-walls
track: B
prio: 55
status: done
owner: frank3
---

# The corpus ladder scan passes one `-Fu` root, so cross-package imports read as compiler walls

Found by Track A, 2026-08-17, while fixing
`bug-a-package-and-sibling-module-resolution-is-the-corpus-wall`.

## The defect

The ladder scan passes only the scanned file's **own** candidate root on `-Fu`.
`tinycss2/bytes.py` does `from webencodings import ...` — a **cross-package**
import. With one root it fails and is recorded as a wall; with both roots it
resolves immediately and the wall moves to `undefined variable (CodecInfo)`, the
known `mimic_codecs` gap already tracked.

## Why this is worth a ticket rather than a tweak

That single row was **6-7 files, the largest entry in the wall table**, and it was
used to rank `webencodings` as the top lever and file a Track A resolution ticket.
The compiler bug it implied does not exist.

**A measurement artefact that survives is worse than a missing measurement**, because
it is actionable and wrong: it does not merely fail to inform, it actively dispatches
work. This one would have kept doing so on every re-scan.

## Fix

Pass every fetched corpus root on `-Fu`, not just the file's own — that is what
CPython does with `sys.path`, and a cross-package import is ordinary Python, not
an edge case. Then re-run the ladder and re-rank; several rows may move.

Track A deliberately did **not** change it: the scan is Track B's instrument, and
redefining another lane's measurement mid-campaign is not Track A's call. Correct
handling, recorded here so the reasoning survives.

## Gate

Re-run the ladder with all roots; `webencodings` should leave the first-wall table
and `CodecInfo` should appear. Publish the corrected table — the old one is cited
in at least two tickets.

## 2026-08-17 (frank3) — FIXED, ladder re-run, table republished

Confirmed as filed, and it was **my** scan and **my** table — the shell loop
passed `-Fu$(dirname $f)`, i.e. only the scanned file's own package directory.

### The fix is a checked-in tool, not a corrected command

`tools/nilpy_ladder.py`. The point of this ticket is that the instrument gets
re-run, so the path rule now lives in a file with the reasoning attached rather
than in a command somebody retypes. For each fetched corpus **two** roots go on
`-Fu`:

```
library_candidates/<name>/          so `import webencodings` finds the package
library_candidates/<name>/<name>/   so a sibling `from .constants import X` resolves
```

which is what CPython's `sys.path` gives a source checkout. Corpora are detected
by the `<name>/<name>/__init__.py` layout, so `reportlab` (an oracle for a
different probe, `src/reportlab/...`) is excluded without a hardcoded list.

One thing the rewrite had to handle: the scan **died** on `errors="strict"`
decoding, because a diagnostic can echo a source line and these corpora carry
non-UTF-8 bytes. `errors="replace"` — a scan that stops at the first odd byte is
its own measurement artefact.

### The corrected table

```
compile: 4/48
    8  undefined variable (digits)
    7  undefined variable (CodecInfo)
    4  missing module: xml_dom
    3  Nil Python: class Filter cannot inherit from itself
    3  missing module: six_moves
    2  missing module: bisect
    2  missing module: genshi_core
    2  missing module: xml_etree_elementtree
    2  missing module: xml_sax_xmlreader
    2  unexpected character (a Unicode identifier)
    1  each: Mapping base, colorsys, copy, lxml, sys, urllib_request,
       xml_sax_saxutils, MULTILINE, lookup
```

**`webencodings` (6) and `constants` (4) are gone from the table entirely** —
both were the artefact, exactly as this ticket predicted. `CodecInfo` appears, as
predicted. The gate is met.

### What the corrected ranking actually says

The two top rows are **single root causes with wide transitive reach**, and both
are already-filed tickets:

| row | files | cause |
| --- | --- | --- |
| `digits` (8) | all of html5lib, through `constants.py` | [[bug-n-assigning-to-a-name-that-collides-with-a-pascal-shim-attribute-fails]] |
| `CodecInfo` (7) | all of tinycss2 + webencodings, through `webencodings/__init__.py` | [[bug-n-a-temporary-receiver-resolves-to-the-shim-type-not-the-user-class]] |

**15 of the 44 failing files sit behind those two tickets.** Neither is a missing
module and neither is package resolution — which is the substantive correction,
because the old table ranked package/sibling resolution as the top lever and it
does not appear in the corrected one at all.

New from this scan and filed:
[[bug-n-a-unicode-identifier-is-rejected-by-the-lexer]] (p25 — 2 files, and both
sit behind `CodecInfo` anyway, so nothing is unblocked by it alone).

### The old numbers are cited in four places, all corrected

`feature-nilpy-six-and-warnings-shims`,
`bug-a-package-and-sibling-module-resolution-is-the-corpus-wall`,
`doc-n-fu-is-how-a-python-package-is-found`,
`feature-nilpy-thirdparty-libraries-as-targets` — each now carries a pointer to
this table. That was the half of the gate that mattered: a corrected instrument
nobody re-runs leaves the wrong numbers in circulation.

## Log
- 2026-08-17 — resolved, commit 831215a86.
