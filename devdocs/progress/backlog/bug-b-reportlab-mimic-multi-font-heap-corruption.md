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

## Residual, still open — and my earlier measurements of it were WORTHLESS

**Correcting this ticket again.** It previously said the residual was "sensitive
to the output path length, not to the font count", citing 0/30 clean runs from
Pascal and NilPy with a short path against 1/30 with a long one. That reasoning
does not hold, and the method was the problem.

The crash rate is **ASLR-sensitive and varies enormously between loops of the
SAME binary**: 4/50 in one run of a loop and 13/20 in the next, with the binary
verified byte-identical (`md5sum` equal; the compiler's executable output is
deterministic — only `.map` files differ between compiles). So **a 0/N run
proves nothing here**, and every "0/30 clean" I recorded was luck being read as
evidence. Path length, font count and compile-then-run all looked causal for the
same reason and none of them survived a control.

What IS solid:

- **One consistent signature**, every catch:
  ```
  SIGSEGV in __crtl_utoa (out=0x7c7c7c7c7c7c7c5a, v=0xFFFFFFFFFFFFFFFF,
                          base=0x7C7C7C46, upper=0x46464646)
  #1..#N  0x7c7c7c7c7c7c7c7c in ?? ()
  ```
  The whole stack is overwritten with `0x7c` (`'|'`), and the garbage arguments
  decode to `0x46464646` (`'FFFF'`). Text is being written over the stack, and
  the fault lands in printf formatting only because that is what runs next.
- It survives the constructor fix (which was a real and separate bug), so it is
  a second defect with the same *shape*: something writing formatted characters
  past a buffer.
- `lib/vendor/pdfgen` driven from C is still clean, so the Pascal layer remains
  the place to look.

**How to measure it properly next time:** fix the binary, run at least 100
iterations, and compare rates only between runs of the SAME executable in the
SAME session — and never treat a zero as a fix. `setarch -R` to disable ASLR
would make the rate stable enough to bisect against.

Next tool per the playbook: `-dPXX_OBJTRACE` with `grep <addr>`.
