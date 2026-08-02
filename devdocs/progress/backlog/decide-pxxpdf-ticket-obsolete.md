---
track: U
prio: 50
type: decision
---

# Close `feature-lib-pxxpdf-reportlab-compat` as obsolete, or keep it?

Filed 2026-08-02 by the Track B agent that picked it up as the ranked top
ticket, found its premises no longer match the tree, and did not want to close a
prio-50 feature ticket unilaterally. Full re-measurement is appended to the
ticket itself; the short version:

- **Vendoring pdfgen: done** since 2026-07-28 (`lib/vendor/pdfgen/`). The
  ticket's "first committed third-party source, policy escalated" framing is
  historical.
- **The design shipped differently.** The ticket specifies a nilpy module named
  `pxxpdf` reached via a `try/except ImportError` fallback. What exists is seven
  `lib/pcl/mimic_reportlab_*.pas` units resolved by the compiler's own import
  mapping, so unmodified `from reportlab.pdfgen import canvas` just works. That
  is arguably a better shape, but it leaves the ticket's name, module layout and
  import strategy obsolete.
- **The API table is implemented**, including `drawImage`, which the ticket
  deferred to v1.x.
- **Its acceptance criterion passes**: a reportlab-using nilpy program compiles,
  runs, and writes a valid `%PDF-1.3` whose text `pdftotext` extracts.

## The fork

**Option A (recommended) — close it, re-file the remainder.** Everything
structural is done, and the one genuinely open item is narrower than the ticket:
*fidelity against the reportlab oracle*. Acceptance asks for output "matching
the reportlab output"; only validity has been shown, never agreement with real
reportlab. Re-file as `feature-lib-reportlab-fidelity-vs-oracle` (differential
test against CPython + reportlab), and let the two crtl follow-ups
([[bug-b-crtl-host-header-and-arity-mismatches-building-pdfgen]]) stand on their
own. Trade-off: loses the ticket's design notes as a live document, though the
appended measurement preserves them.

**Option B — keep it open, rewrite it in place** to describe the mimic design
and the fidelity gap. Keeps one thread and its history. Trade-off: the slug
still says `pxxpdf`, a name that no longer exists anywhere in the tree, which is
how a ticket ends up misleading the next reader.

**Option C — build the literal `pxxpdf` module too**, as the ticket specifies,
alongside the mimic units. Only worth it if the `try/except ImportError` idiom
matters for its own sake (code that must run unmodified under both CPython and
nilpy *without* compiler import mapping). Otherwise it is a second way to do
what already works.

My recommendation is **A**, on the grounds that the ticket's own acceptance test
passes and its name no longer refers to anything real. But which of these is
right depends on whether the `pxxpdf` module name was ever wanted for its own
sake, which I cannot tell from the code or the ticket.
