---
track: B
prio: 55
type: bug
summary: "A reportlab-mimic document using four or more distinct fonts crashes INTERMITTENTLY — ~1 run in 6, and 3 in 10 under -dPXX_HEAP_DEBUG. One font is stable. Heap corruption, not a missing feature"
---

# reportlab mimic: 4+ distinct fonts corrupts the heap

- **Type:** bug (memory corruption, intermittent) — Track B (`lib/pcl`)
- **Opened:** 2026-08-09
- **Found by:** the differential harness built for
  [[feature-lib-reportlab-fidelity-vs-oracle]] — `tools/reportlab_diff.py`,
  which reproduces it on 2 of its 3 cases.

## Repro

```python
from reportlab.pdfgen import canvas
c = canvas.Canvas("/tmp/out.pdf")
c.setFont("Helvetica", 12);   c.drawString(72, 720, "Hello world")
c.setFont("Helvetica", 24);   c.drawString(72, 680, "Bigger text")
c.setFont("Times-Roman", 14); c.drawString(100, 640, "Times at 14")
c.setFont("Courier", 10);     c.drawString(150, 600, "Courier 10")
c.showPage(); c.save()
```

```
$ pxx -Fulib/pcl repro.py && ./repro     # 6 fresh builds
139 0 0 0 0 0
$ pxx -dPXX_HEAP_DEBUG -Fulib/pcl repro.py && ./repro   # 10 runs
3/10 crashed
```

## What is known

- **Font COUNT, not a particular font.** Three distinct fonts is stable; four
  crashes, with any four. `Courier` alone, and `Helvetica + Courier`, are fine.
- **One font with many drawStrings is stable** — the harness's `positions` case
  (4 strings, 1 font) passes every time and matches reportlab exactly.
- **It is heap corruption**, not a null deref: `-dPXX_HEAP_DEBUG` *raises* the
  crash rate (3/10 vs ~1/6), which is what that flag does when freed memory is
  being reused — it poisons freed bytes to `$DD` instead of leaving a
  plausible recycled neighbour.
- **Not the vendored writer, and not the C frontend.** `lib/vendor/pdfgen` was
  driven directly from C with the same four fonts, compiled by BOTH gcc and pxx:
  both print all four and exit 0. So `pdf_set_font`'s per-font object allocation
  is fine and pxx compiles it correctly. The fault is in the Pascal layer,
  `lib/pcl/mimic_reportlab_pdfgen.pas`.
- **Pre-existing, merely exposed.** Before 2026-08-09 the one-argument
  `canvas.Canvas("out.pdf")` segfaulted deterministically in the constructor, so
  no multi-font document ever got far enough to hit this.

## Narrowed further, same day — it needs BOTH ingredients

| case | crashes |
| --- | --- |
| 4 `setFont` calls, NO `drawString` | **0 / 12** |
| 1 font, 4 `drawString` calls | **0 / 12** |
| 4 fonts, one `drawString` after each | **2 / 12** |

So neither switching fonts nor drawing text is sufficient alone: the corruption
needs text drawn AFTER a font switch, repeatedly. That points at the interaction
between `pdf_set_font`'s new font object and the `pdf_add_text` that follows it,
not at either operation on its own.

**Both exonerations re-verified over many runs**, since a single clean run is
worth nothing for an intermittent fault:

- `lib/vendor/pdfgen` driven from C with the same 4 fonts + 4 texts:
  **0 / 25 crashes pxx-compiled, 0 / 25 gcc-compiled**. The vendored writer and
  the C frontend are both clear; the fault is in the Pascal layer.
- `realloc` under pdfgen's exact growth pattern (double a buffer 8 times with
  interleaved allocations, 200 rounds, contents verified): **0 mismatches** on
  both gcc and pxx. Not the allocator's grow path.

## Where to look first

Every `AnsiString` passed to the C backend now goes through `PChar()` (that was
its own defect, fixed the same day — `drawString`'s text was raw). The remaining
suspects are the shim's own per-font bookkeeping and the lifetime of strings
handed across the Pascal/C boundary while more objects are being allocated:
`pdf_set_font` copies the name with `strncpy`, but `pdf_add_text` holds its
`const char *` for the duration of the call while the writer may allocate.

`-dPXX_OBJTRACE` plus `grep <addr>` is the next tool — the playbook's
retain/release trace — since the corruption tracks object COUNT.

## Why prio 55 rather than the parent ticket's 45

It is a crash in a shipped shim on ordinary input: a document with a heading
font, a body font, a bold and a monospace is not exotic, it is a typical page.
The parent fidelity ticket cannot be finished while two of its three cases
cannot be run.

## Gate

`tools/reportlab_diff.py` green on all cases across repeated runs, and the
`-dPXX_HEAP_DEBUG` build clean over at least 50 runs.
