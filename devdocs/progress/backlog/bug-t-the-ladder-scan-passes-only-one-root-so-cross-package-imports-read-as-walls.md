---
slug: bug-t-the-ladder-scan-passes-only-one-root-so-cross-package-imports-read-as-walls
track: B
prio: 55
status: backlog
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
