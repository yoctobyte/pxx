---
track: B
prio: 30
type: bug
summary: "ROOT-CAUSED to bug-p-constructor-with-a-defaulted-variant-param-corrupts-memory and largely fixed by a workaround. The original font-count table was WRONG — an artefact of small samples against an intermittent fault. A rarer residual remains"
---

# reportlab mimic: 4+ distinct fonts corrupts the heap

- **Type:** bug (memory corruption, intermittent) — Track B (`lib/pcl`)
- **Opened:** 2026-08-09
- **Found by:** the differential harness built for
  [[feature-lib-reportlab-fidelity-vs-oracle]] — `tools/reportlab_diff.py`,
  which reproduces it on 2 of its 3 cases.

## ROOT-CAUSED 2026-08-09 — and my first diagnosis here was wrong

**Retracting the font-count claim.** This ticket originally said "font COUNT,
not a particular font", with a table showing 4 setFont+draw at 2/12 and one font
at 0/12. That was **an artefact of small samples against an intermittent
fault**: the `positions` case, which uses ONE font, later failed on three
consecutive harness runs. Do not trust the table that used to be here; it is
removed rather than corrected, because its shape was the error.

**The actual cause** is [[bug-p-constructor-with-a-defaulted-variant-param-corrupts-memory]]:
a class constructor with a defaulted `Variant` parameter smashes the stack when
the caller omits the argument. `Canvas.Create(filename, pagesize = 0)` is
exactly that shape, and `canvas.Canvas("out.pdf")` is exactly that call.

How it was found, since the path matters: gdb on the faulting run showed the
crash inside `__crtl_utoa` — printf formatting, nowhere near PDF code — with the
whole stack overwritten by ASCII (`0x7c7c7c7c…` = `'|'`, argument bytes decoding
to `'FFFF'`). Reduction then went library -> Pascal-direct -> 12 lines with no
library at all.

Driving the mimic **from Pascal** made it deterministic — 25/25 crashes — which
is what turned an unfixable intermittent bug into a tractable one. From NilPy
the same defect is intermittent because the stack layout differs.

**Fixed here by a registered workaround** (`devdocs/dev/track-b-workarounds.md`):
two constructors, the one-argument form forwarding an explicit `0`, so the
defaulted-parameter path is never taken. Pascal-direct went 25/25 -> **0/30**,
and the harness's `text_fonts` and `positions` cases now pass consistently and
match reportlab to 0.000029 pt.

## Residual, still open

`tools/reportlab_diff.py`'s `many_fonts` case still fails inside the harness,
while the same five fonts run 0/30 clean from both Pascal and NilPy when written
to a SHORT output path. With a 55-character path it reproduces at 1/30. So there
is a second, rarer corruption that is sensitive to the output path length, not
to the font count. Prio dropped to 30: the common paths are fixed and the
remaining trigger is narrow, but it is real and should not be closed.

**One more raw-string call found and fixed, though it was NOT the residual:**
`pdf_save(doc, outPath)` passed an `AnsiString` straight to a `const char *`.
My earlier sweep for exactly this defect MISSED it because the grep excluded
`pdf_save` by name — the sibling check was run with a filter that hid one of the
siblings. Fixed (`PChar(outPath)`), and it is correct on its own terms, but the
long-path case still reproduces at 1/40, so the residual is elsewhere. Every
remaining call to the C backend now passes only numbers.

Next tool per the playbook: `-dPXX_OBJTRACE` with `grep <addr>`, and a long-path
Pascal-direct repro to try to make it deterministic the way the ctor one was.

## Original repro